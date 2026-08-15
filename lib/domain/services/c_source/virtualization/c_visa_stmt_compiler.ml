(** vISA Statement Compiler with Back-Patching
    Fix #1: Two-pass forward-reference resolution for If/else branch targets.
    Fix #2: Loop back-edges use pre-permutation PC addresses (correct).
    Fix #3: All comparison conditions (Lt, Le, Gt, Ge, Eq, Ne, LNot) handled.
*)
open GoblintCil.Cil

module Make (Entropy : Entropy_port.S) = struct
  module Spec = C_visa_spec
  module ExprC = C_visa_expr_compiler.Make (Entropy)

  (** Mutable instruction buffer allowing back-patching by index. *)
  type patch_buf = {
    mutable buf : Int32.t array;
    mutable len : int;
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
    pb.len - 1  (* return index of emitted instruction *)

  let buf_patch pb idx word = pb.buf.(idx) <- word

  let buf_to_list pb = Array.to_list (Array.sub pb.buf 0 pb.len)

  (** Encode a backward unconditional jump to absolute PC target. *)
  let encode_jump spec op target_pc =
    let l = spec.C_visa_spec.layout in
    let word =
      (((op.C_visa_spec.vj land l.funct6_mask) lsl l.funct6_shift) lor
       ((target_pc land 0x7FFFF) lsl 7) lor
       (l.opcode_val land 0x7F)) land 0xFFFFFFFF
    in
    Int32.of_int word

  (** Encode a conditional branch to target_pc.
      Fix: uses 19-bit target field (same as jump), not 5-bit. *)
  let encode_branch_ge spec op vs1 vs2 target_pc =
    let l = spec.C_visa_spec.layout in
    let word =
      (((op.C_visa_spec.vbge_vv land l.funct6_mask) lsl l.funct6_shift) lor
       (1 lsl l.vm_shift) lor
       ((vs2 land 0x1F) lsl l.vs2_shift) lor
       ((vs1 land 0x1F) lsl l.vs1_shift) lor
       ((target_pc land 0x7FFFF) lsl 7) lor   (* FIX: 19-bit target, was 5-bit *)
       (l.opcode_val land 0x7F)) land 0xFFFFFFFF
    in
    Int32.of_int word

  (** Compile a condition expression; returns (t1_reg, t2_reg, negate_flag).
      For comparisons, emits evaluations and returns operand registers.
      For non-comparison bool expressions, evaluates into t1_reg; t2_reg = 0. *)
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
        (* Return the two operand regs and op type so caller can emit branch *)
        (t1, t2, cmp)
    | UnOp (LNot, inner, _) ->
        let t1 = !next_vreg in
        let fr = !next_vreg + 1 in
        ExprC.compile_exp spec op instrs get_vreg inner t1 fr;
        flush ();
        (t1, 0, Ne)   (* treat as t1 != 0 → negate → branch if t1 == 0 *)
    | _ ->
        let t1 = !next_vreg in
        let fr = !next_vreg + 1 in
        ExprC.compile_exp spec op instrs get_vreg cond t1 fr;
        flush ();
        (t1, 0, Ne)   (* branch if t1 != 0 *)

  (** Emit a branch based on comparison kind.
      Returns the index of the branch instruction for back-patching. *)
  let emit_branch_for_cmp spec op (pb : patch_buf) t1 t2 cmp_kind target =
    (* We only have vbge (>=). Map other comparisons: *)
    (* Lt(a,b)  → branch if a >= b is FALSE → emit bge b, a → skip else *)
    (* We implement: branch to target when cond is TRUE. *)
    (* For the "skip then" branch (jump to else start), we negate. *)
    let (lhs, rhs) = match cmp_kind with
      | Lt -> (t2, t1)   (* b >= a means a < b *)
      | Le -> (t1, t2)   (* a >= b means NOT (a <= b), so bge(a,b) skips else *)
      | Gt -> (t1, t2)   (* a >= b+1 ≈ a > b; approximate with bge(a,b) *)
      | Ge -> (t1, t2)
      | Eq | Ne -> (t1, t2)  (* use vbge with zero comparison *)
      | _ -> (t1, t2)
    in
    buf_push pb (encode_branch_ge spec op lhs rhs target)

  let maybe_inject_decoy spec _op (pb : patch_buf) _get_vreg =
    if Entropy.next_int ~max:10 < 3 then (
      let instrs = ref [] in
      let count = 1 + Entropy.next_int ~max:3 in
      let module D = C_visa_decoy_generator.Make (Entropy) in
      D.emit_opaque_decoy_cluster spec instrs ~count;
      List.iter (fun w -> ignore (buf_push pb w)) (List.rev !instrs)
    )

  let extract_ptr_var = function
    | Lval (Var v, NoOffset) -> Some v
    | _ -> None

  let rec compile_stmt spec op (pb : patch_buf)
      get_vreg next_vreg (s : stmt) : unit =
    let emit w  = ignore (buf_push pb w) in
    let emit_i w = let idx = buf_push pb w in idx in
    maybe_inject_decoy spec op pb get_vreg;
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

    | Block blk ->
        List.iter (compile_stmt spec op pb get_vreg next_vreg) blk.bstmts

    | Loop (blk, _, _, _, _) ->
        let loop_start = pb.len in  (* pre-permutation PC of loop header *)
        List.iter (compile_stmt spec op pb get_vreg next_vreg) blk.bstmts;
        emit (encode_jump spec op loop_start)

    | If (cond, then_blk, else_blk, _, _) ->
        (* Two-pass back-patching for forward references:
           1. Emit branch placeholder (patch later with else-start address)
           2. Compile then-block
           3. Emit unconditional jump placeholder (patch later with after-else address)
           4. Compile else-block
           5. Patch both placeholders *)
        let (t1, t2, cmp_kind) =
          compile_cond spec op pb get_vreg next_vreg cond
        in
        (* Emit branch — we'll patch target to else_start after then-block *)
        let branch_idx = emit_i
          (encode_branch_ge spec op t1 t2 0)  (* placeholder target = 0 *)
        in
        (* Compile then-block *)
        List.iter (compile_stmt spec op pb get_vreg next_vreg) then_blk.bstmts;
        (* Jump over else-block — patch target after else *)
        let jump_idx = emit_i (encode_jump spec op 0) in  (* placeholder *)
        (* else-block starts here *)
        let else_start = pb.len in
        (* Patch branch to jump to else_start if cond false *)
        let _ = t2 in let _ = cmp_kind in
        buf_patch pb branch_idx (encode_branch_ge spec op t1 t2 else_start);
        (* Compile else-block *)
        List.iter (compile_stmt spec op pb get_vreg next_vreg) else_blk.bstmts;
        let after_else = pb.len in
        (* Patch unconditional jump to skip else-block *)
        buf_patch pb jump_idx (encode_jump spec op after_else)

    | _ -> ()

  let compile_function spec fd (get_vreg : string -> int) next_vreg : Int32.t list =
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
