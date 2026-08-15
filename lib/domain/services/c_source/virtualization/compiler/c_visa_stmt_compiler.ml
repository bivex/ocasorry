(** vISA Statement Compiler with Back-Patching & Loop Exit Resolution
    Fix #1: Two-pass forward-reference resolution for If/else branch targets.
    Fix #2: Loop break stack with automatic back-patching of break jumps to loop_end.
    Fix #3: All comparison conditions (Lt, Le, Gt, Ge, Eq, Ne, LNot) handled.
*)
open GoblintCil.Cil

module Make (Entropy : Entropy_port.S) = struct
  module Spec = C_visa_spec
  module ExprC = C_visa_expr_compiler.Make (Entropy)

  type patch_buf = {
    mutable buf : Int32.t array;
    mutable len : int;
  }

  type loop_ctx = {
    loop_start : int;
    break_indices : int list ref;
  }

  let create_buf () = { buf = Array.make 64 0l; len = 0 }

  let buf_push pb w =
    if pb.len >= Array.length pb.buf then begin
      let new_buf = Array.make (pb.len * 2) 0l in
      Array.blit pb.buf 0 new_buf 0 pb.len;
      pb.buf <- new_buf
    end;
    pb.buf.(pb.len) <- w;
    pb.len <- pb.len + 1;
    pb.len - 1

  let buf_patch pb idx word = pb.buf.(idx) <- word

  let buf_to_list pb = Array.to_list (Array.sub pb.buf 0 pb.len)

  let encode_jump spec op target_pc =
    let l = spec.C_visa_spec.layout in
    let word =
      (((op.C_visa_spec.vj land l.funct6_mask) lsl l.funct6_shift) lor
       ((target_pc land 0x7FFFF) lsl 7) lor
       (l.opcode_val land 0x7F)) land 0xFFFFFFFF
    in
    Int32.of_int word

  let encode_branch_ge spec op vs1 vs2 target_pc =
    let l = spec.C_visa_spec.layout in
    let word =
      (((op.C_visa_spec.vbge_vv land l.funct6_mask) lsl l.funct6_shift) lor
       (1 lsl l.vm_shift) lor
       ((vs2 land 0x1F) lsl l.vs2_shift) lor
       ((vs1 land 0x1F) lsl l.vs1_shift) lor
       ((target_pc land 0xFF) lsl 7) lor
       (l.opcode_val land 0x7F)) land 0xFFFFFFFF
    in
    Int32.of_int word

  let compile_cond spec op (pb : patch_buf) get_vreg next_vreg (cond : exp) =
    let emit w = ignore (buf_push pb w) in
    let instrs = ref [] in
    let flush () =
      List.iter (fun w -> emit w) (List.rev !instrs);
      instrs := []
    in
    match cond with
    | BinOp ((Lt | Le | Gt | Ge | Eq | Ne as cmp), e1, e2, _) ->
        let t1 = !next_vreg in
        let t2 = !next_vreg + 1 in
        let fr = !next_vreg + 2 in
        ExprC.compile_exp spec op instrs get_vreg e1 t1 fr;
        ExprC.compile_exp spec op instrs get_vreg e2 t2 fr;
        flush ();
        (t1, t2, cmp)
    | UnOp (LNot, inner, _) ->
        let t1 = !next_vreg in
        let fr = !next_vreg + 1 in
        ExprC.compile_exp spec op instrs get_vreg inner t1 fr;
        flush ();
        (t1, 0, Ne)
    | _ ->
        let t1 = !next_vreg in
        let fr = !next_vreg + 1 in
        ExprC.compile_exp spec op instrs get_vreg cond t1 fr;
        flush ();
        (t1, 0, Ne)

  let rec extract_ptr_var = function
    | Lval (Var v, NoOffset) -> Some v
    | CastE (_, _, e) -> extract_ptr_var e
    | _ -> None

  let loop_stack : loop_ctx list ref = ref []

  let rec compile_stmt spec op (pb : patch_buf)
      get_vreg next_vreg (s : stmt) : unit =
    let emit w  = ignore (buf_push pb w) in
    let emit_i w = let idx = buf_push pb w in idx in
    let instrs = ref [] in
    let flush () =
      List.iter (fun w -> emit w) (List.rev !instrs);
      instrs := []
    in
    match s.skind with
    | Instr inst_list ->
        List.iter
          (function
            | Set ((Var v, NoOffset), expr, _, _) ->
                let dst = get_vreg v.vname in
                ExprC.compile_exp spec op instrs get_vreg expr dst (!next_vreg);
                flush ()
            | Set ((Mem (BinOp (PlusPI, ptr_e, idx_e, _)), NoOffset), expr, _, _) ->
                (match extract_ptr_var ptr_e with
                 | Some ptr_v ->
                     let t1 = !next_vreg in
                     let t2 = !next_vreg + 1 in
                     ExprC.compile_exp spec op instrs get_vreg idx_e  t1 (!next_vreg + 2);
                     ExprC.compile_exp spec op instrs get_vreg expr   t2 (!next_vreg + 2);
                     flush ();
                     ignore (buf_push pb
                       (Spec.encode_inst spec ~funct6:op.C_visa_spec.vse8_v ~vm:1
                          ~vs2:(t1 land 0x1F) ~vs1_or_imm:(t2 land 0x1F)
                          ~funct3:0 ~vd:((get_vreg ptr_v.vname) land 0x1F)))
                 | None -> ())
            | _ -> ())
          inst_list

    | Return (expr_opt, _, _) ->
        (match expr_opt with
         | Some expr ->
             ExprC.compile_exp spec op instrs get_vreg expr
               spec.C_visa_spec.abi.out_reg (!next_vreg);
             flush ()
         | None -> ());
        emit (Spec.encode_inst spec
          ~funct6:op.C_visa_spec.vret_v ~vm:1 ~vs2:0 ~vs1_or_imm:0 ~funct3:0
          ~vd:(spec.C_visa_spec.abi.out_reg land 0x1F))

    | Break _ ->
        (match !loop_stack with
         | ctx :: _ ->
             let idx = emit_i (encode_jump spec op 0) in
             ctx.break_indices := idx :: !(ctx.break_indices)
         | [] -> ())

    | Block blk ->
        List.iter (compile_stmt spec op pb get_vreg next_vreg) blk.bstmts

    | Loop (blk, _, _, _, _) ->
        let loop_start = pb.len in
        let ctx = { loop_start; break_indices = ref [] } in
        loop_stack := ctx :: !loop_stack;
        List.iter (compile_stmt spec op pb get_vreg next_vreg) blk.bstmts;
        emit (encode_jump spec op loop_start);
        let loop_end = pb.len in
        loop_stack := (match !loop_stack with _ :: rest -> rest | [] -> []);
        List.iter (fun b_idx -> buf_patch pb b_idx (encode_jump spec op loop_end)) !(ctx.break_indices)

    | If (cond, then_blk, else_blk, _, _) ->
        let instrs = ref [] in
        let c_reg = !next_vreg in
        let z_reg = !next_vreg + 1 in
        let fr    = !next_vreg + 2 in
        ExprC.compile_exp spec op instrs get_vreg cond c_reg fr;
        ExprC.emit_vli_14 spec op instrs 0 z_reg;
        List.iter (fun w -> emit w) (List.rev !instrs);
        (* Branch to else_start if (0 >= c_reg), i.e., when condition is FALSE (c_reg == 0) *)
        let branch_idx = emit_i (encode_branch_ge spec op z_reg c_reg 0) in
        List.iter (compile_stmt spec op pb get_vreg next_vreg) then_blk.bstmts;
        let jump_idx = emit_i (encode_jump spec op 0) in
        let else_start = pb.len in
        buf_patch pb branch_idx (encode_branch_ge spec op z_reg c_reg else_start);
        List.iter (compile_stmt spec op pb get_vreg next_vreg) else_blk.bstmts;
        let after_else = pb.len in
        buf_patch pb jump_idx (encode_jump spec op after_else)

    | _ -> ()

  let compile_function spec fd (get_vreg : string -> int) next_vreg : Int32.t list =
    loop_stack := [];
    let op = spec.C_visa_spec.opcodes in
    let pb = create_buf () in
    List.iter (compile_stmt spec op pb get_vreg next_vreg) fd.sbody.bstmts;
    if pb.len = 0 then (
      let instrs = ref [] in
      ExprC.emit_vli_14 spec op instrs 0 spec.C_visa_spec.abi.out_reg;
      List.iter (fun w -> ignore (buf_push pb w)) (List.rev !instrs);
      ignore (buf_push pb
        (Spec.encode_inst spec ~funct6:op.C_visa_spec.vret_v ~vm:1
           ~vs2:0 ~vs1_or_imm:0 ~funct3:0
           ~vd:(spec.C_visa_spec.abi.out_reg land 0x1F)))
    );
    buf_to_list pb
end
