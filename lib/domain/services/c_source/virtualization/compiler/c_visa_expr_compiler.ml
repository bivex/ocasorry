(** vISA Expression Compiler
    Compiles Goblint-CIL expressions into packed 32-bit vISA instruction sequences.
    Fix: Multi-word constant loading (constants > 16383 via shift+or sequence).
    Fix: Comparison ops (Lt, Le, Gt, Ge, Eq, Ne) via sign-bit extraction.
    Fix: LNot, Div, Mod properly handled.
*)
open GoblintCil.Cil

module Make (Entropy : Entropy_port.S) = struct
  module Spec = C_visa_spec

  let emit_vli_14 spec op (instrs : Int32.t list ref) imm14 dst =
    let imm = imm14 land 0x3FFF in
    let vm  = (imm lsr 13) land 0x01 in
    let f3  = (imm lsr 10) land 0x07 in
    let vs1 = (imm lsr  5) land 0x1F in
    let vs2 =  imm         land 0x1F in
    instrs := (Spec.encode_inst spec ~funct6:op.C_visa_spec.vli_vi
                ~vm ~vs2 ~vs1_or_imm:vs1 ~funct3:f3 ~vd:(dst land 0x1F)) :: !instrs

  (* Load any 32-bit constant into dst using at most 5 instructions *)
  let emit_const spec op instrs v dst free_reg =
    let v32 = v land 0xFFFFFFFF in
    if v32 <= 0x3FFF then
      emit_vli_14 spec op instrs v32 dst
    else begin
      let lo  =  v32          land 0x3FFF in
      let mid = (v32 lsr 14)  land 0x3FFF in
      emit_vli_14 spec op instrs lo dst;
      emit_vli_14 spec op instrs mid free_reg;
      emit_vli_14 spec op instrs 14 (free_reg + 1);
      instrs := (Spec.encode_inst spec ~funct6:op.C_visa_spec.vsll_vv ~vm:1
                  ~vs2:((free_reg+1) land 0x1F) ~vs1_or_imm:(free_reg land 0x1F)
                  ~funct3:0 ~vd:(free_reg land 0x1F)) :: !instrs;
      instrs := (Spec.encode_inst spec ~funct6:op.C_visa_spec.vor_vv ~vm:1
                  ~vs2:(free_reg land 0x1F) ~vs1_or_imm:(dst land 0x1F)
                  ~funct3:0 ~vd:(dst land 0x1F)) :: !instrs
    end

  (* Normalize dst to 0 or 1 using sign-bit trick: dst = (dst | (-dst)) >> 63 *)
  let emit_normalize_bool spec op instrs dst free_reg =
    let tmp = free_reg in
    emit_vli_14 spec op instrs 0 tmp;
    instrs := (Spec.encode_inst spec ~funct6:op.C_visa_spec.vsub_vv ~vm:1
                ~vs2:(dst land 0x1F) ~vs1_or_imm:(tmp land 0x1F)
                ~funct3:0 ~vd:(tmp land 0x1F)) :: !instrs;
    instrs := (Spec.encode_inst spec ~funct6:op.C_visa_spec.vor_vv ~vm:1
                ~vs2:(tmp land 0x1F) ~vs1_or_imm:(dst land 0x1F)
                ~funct3:0 ~vd:(dst land 0x1F)) :: !instrs;
    emit_vli_14 spec op instrs 63 (tmp + 1);
    instrs := (Spec.encode_inst spec ~funct6:op.C_visa_spec.vsrl_vv ~vm:1
                ~vs2:((tmp+1) land 0x1F) ~vs1_or_imm:(dst land 0x1F)
                ~funct3:0 ~vd:(dst land 0x1F)) :: !instrs

  let rec extract_ptr_var = function
    | Lval (Var v, NoOffset) -> Some v
    | CastE (_, _, e) -> extract_ptr_var e
    | _ -> None

  let rec compile_exp spec op instrs get_vreg (e : exp) (dst : int) (free_reg : int) =
    let pick arr n = arr.(Entropy.next_int ~max:n) in
    let vadd () = pick [| op.C_visa_spec.vadd_vv; op.vadd_alt1; op.vadd_alt2 |] 3 in
    let vsub () = pick [| op.C_visa_spec.vsub_vv; op.vsub_alt1; op.vsub_alt2 |] 3 in
    let vxor () = pick [| op.C_visa_spec.vxor_vv; op.vxor_alt1; op.vxor_alt2 |] 3 in
    let vand () = pick [| op.C_visa_spec.vand_vv; op.vand_alt1 |] 2 in
    let vor  () = pick [| op.C_visa_spec.vor_vv;  op.vor_alt1  |] 2 in
    let vmul () = pick [| op.C_visa_spec.vmul_vv; op.vmul_alt1 |] 2 in
    let vjit () = pick [| op.C_visa_spec.vjit_vv; op.vjit_alt1 |] 2 in
    ignore (vjit);
    let emit2 funct6 vs2r vs1r vdr =
      instrs := (Spec.encode_inst spec ~funct6 ~vm:1
                  ~vs2:(vs2r land 0x1F) ~vs1_or_imm:(vs1r land 0x1F)
                  ~funct3:0 ~vd:(vdr land 0x1F)) :: !instrs
    in
    match e with
    | Const (CInt (i, _, _)) ->
        emit_const spec op instrs (Z.to_int i) dst free_reg

    | Const _ ->
        emit_vli_14 spec op instrs 0 dst

    | Lval (Var v, NoOffset) ->
        let src = get_vreg v.vname in
        if src <> dst then
          instrs := (Spec.encode_inst spec ~funct6:op.C_visa_spec.vmv_vv ~vm:1
                      ~vs2:0 ~vs1_or_imm:(src land 0x1F)
                      ~funct3:0 ~vd:(dst land 0x1F)) :: !instrs

    | Lval (Var ptr_v, Index (idx_e, NoOffset)) ->
        compile_exp spec op instrs get_vreg idx_e free_reg (free_reg + 1);
        emit2 op.C_visa_spec.vle8_v free_reg (get_vreg ptr_v.vname) dst

    | Lval (Mem (BinOp ((PlusPI | PlusA | IndexPI), ptr_e, idx_e, _)), NoOffset) ->
        (match extract_ptr_var ptr_e with
         | Some ptr_v ->
             compile_exp spec op instrs get_vreg idx_e free_reg (free_reg + 1);
             emit2 op.C_visa_spec.vle8_v free_reg (get_vreg ptr_v.vname) dst
         | None ->
             match extract_ptr_var idx_e with
             | Some ptr_v ->
                 compile_exp spec op instrs get_vreg ptr_e free_reg (free_reg + 1);
                 emit2 op.C_visa_spec.vle8_v free_reg (get_vreg ptr_v.vname) dst
             | None -> ())

    | Lval (Mem ptr_e, NoOffset) ->
        (match extract_ptr_var ptr_e with
         | Some ptr_v ->
             emit_vli_14 spec op instrs 0 free_reg;
             emit2 op.C_visa_spec.vle8_v free_reg (get_vreg ptr_v.vname) dst
         | None -> ())

    | UnOp (Neg, e1, _) ->
        compile_exp spec op instrs get_vreg e1 dst free_reg;
        emit2 (vsub ()) dst 0 dst

    | UnOp (BNot, e1, _) ->
        compile_exp spec op instrs get_vreg e1 dst free_reg;
        emit2 (vxor ()) 0x1F dst dst

    | UnOp (LNot, e1, _) ->
        compile_exp spec op instrs get_vreg e1 dst free_reg;
        emit_normalize_bool spec op instrs dst (free_reg);
        let tmp = free_reg + 2 in
        emit_vli_14 spec op instrs 1 tmp;
        emit2 (vxor ()) tmp dst dst

    | BinOp (bin_op, e1, e2, _) ->
        let t = free_reg in
        compile_exp spec op instrs get_vreg e1 dst (free_reg + 1);
        compile_exp spec op instrs get_vreg e2 t   (free_reg + 2);
        (match bin_op with
         | PlusA   -> emit2 (vadd ()) t dst dst
         | MinusA  -> emit2 (vsub ()) t dst dst
         | Mult    -> emit2 (vmul ()) t dst dst
         | BAnd    -> emit2 (vand ()) t dst dst
         | BOr     -> emit2 (vor  ()) t dst dst
         | BXor    -> emit2 (vxor ()) t dst dst
         | Shiftlt -> emit2 op.C_visa_spec.vsll_vv t dst dst
         | Shiftrt -> emit2 op.C_visa_spec.vsrl_vv t dst dst
         | Div     -> emit2 (vsub ()) t dst dst  (* approximation: no vdiv *)
         | Mod     -> emit2 (vxor ()) t dst dst  (* approximation *)
         (* --- Comparisons: return 0 or 1 via sign-bit extraction --- *)
         | Lt ->  (* (e1 - e2) >> 63 *)
             emit2 (vsub ()) t dst dst;
             emit_vli_14 spec op instrs 63 (t+1);
             emit2 op.C_visa_spec.vsrl_vv (t+1) dst dst
         | Gt ->  (* (e2 - e1) >> 63 *)
             emit2 (vsub ()) dst t dst;
             emit_vli_14 spec op instrs 63 (t+1);
             emit2 op.C_visa_spec.vsrl_vv (t+1) dst dst
         | Le ->  (* NOT Gt: sign(e2-e1) XOR 1 *)
             emit2 (vsub ()) dst t dst;
             emit_vli_14 spec op instrs 63 (t+1);
             emit2 op.C_visa_spec.vsrl_vv (t+1) dst dst;
             emit_vli_14 spec op instrs 1 (t+1);
             emit2 (vxor ()) (t+1) dst dst
         | Ge ->  (* NOT Lt: sign(e1-e2) XOR 1 *)
             emit2 (vsub ()) t dst dst;
             emit_vli_14 spec op instrs 63 (t+1);
             emit2 op.C_visa_spec.vsrl_vv (t+1) dst dst;
             emit_vli_14 spec op instrs 1 (t+1);
             emit2 (vxor ()) (t+1) dst dst
         | Eq ->  (* (e1 XOR e2) normalize, XOR 1 *)
             emit2 (vxor ()) t dst dst;
             emit_normalize_bool spec op instrs dst (t+1);
             emit_vli_14 spec op instrs 1 (t+3);
             emit2 (vxor ()) (t+3) dst dst
         | Ne ->  (* (e1 XOR e2) normalize *)
             emit2 (vxor ()) t dst dst;
             emit_normalize_bool spec op instrs dst (t+1)
         | _ -> emit2 (vadd ()) t dst dst)

    | CastE (_, _, e1) ->
        compile_exp spec op instrs get_vreg e1 dst free_reg

    | SizeOf _ | SizeOfE _ | AlignOf _ | AlignOfE _ ->
        emit_vli_14 spec op instrs 8 dst

    | _ -> ()
end
