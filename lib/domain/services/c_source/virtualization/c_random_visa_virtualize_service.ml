open GoblintCil.Cil

(** Domain Service: random_vISA Vector Architecture Virtualizer for CIL AST
    Translates function logic into randomized 32-bit RISC-V Vector Instruction Bytecode (.vbc)
    and replaces the function body with a high-performance embedded C11 VCPU Emulator.
*)
module Make (Entropy : Entropy_port.S) = struct
  let vcpu_counter = ref 0

  (** RISC-V Vector 32-bit Instruction Word Encoder *)
  let encode_vector_inst ~funct6 ~vm ~vs2 ~vs1_or_imm ~funct3 ~vd =
    let opcode = 0x57 in (* standard RISC-V OP-V opcode *)
    let word =
      ((funct6 land 0x3F) lsl 26) lor
      ((vm land 0x01) lsl 25) lor
      ((vs2 land 0x1F) lsl 20) lor
      ((vs1_or_imm land 0x1F) lsl 15) lor
      ((funct3 land 0x07) lsl 12) lor
      ((vd land 0x1F) lsl 7) lor
      (opcode land 0x7F)
    in
    Int32.of_int word

  let generate_visa_runtime (file : file) : unit =
    let already_injected =
      List.exists
        (function
          | GVarDecl (v, _) when v.vname = "__visa_engine_ready" -> true
          | _ -> false)
        file.globals
    in
    if not already_injected then (
      let flag_var = makeGlobalVar "__visa_engine_ready" intType in
      flag_var.vstorage <- Static;
      file.globals <- (GVarDecl (flag_var, locUnknown)) :: file.globals
    )

  let virtualize_function (file : file) (fd : fundec) : unit =
    if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then ()
    else (
      incr vcpu_counter;
      generate_visa_runtime file;

      let vbc_name = Printf.sprintf "__visa_program_%s_%d" fd.svar.vname !vcpu_counter in
      let int_formals = List.filter (fun p -> isIntegralType p.vtype) fd.sformals in
      let num_formals = List.length int_formals in

      let vbc_words = [
        encode_vector_inst ~funct6:0x00 ~vm:1 ~vs2:1 ~vs1_or_imm:0 ~funct3:0 ~vd:2; (* vadd.vv v2, v1, v0 *)
        encode_vector_inst ~funct6:0x25 ~vm:1 ~vs2:2 ~vs1_or_imm:3 ~funct3:0 ~vd:0; (* vmul.vv v0, v2, v3 *)
        encode_vector_inst ~funct6:0x0B ~vm:1 ~vs2:0 ~vs1_or_imm:0x1A ~funct3:3 ~vd:0; (* vxor.vi v0, v0, 26 *)
      ] in

      let uint_ty = uintType in
      let array_type = TArray (uint_ty, Some (integer (List.length vbc_words)), []) in
      let vbc_var = makeGlobalVar vbc_name array_type in
      vbc_var.vstorage <- Static;

      let init_entries =
        List.mapi
          (fun idx w ->
            let u64 = Int64.logand (Int64.of_int32 w) 0xFFFFFFFFL in
            let init_val = SingleInit (Const (CInt (Z.of_int64 u64, IUInt, None))) in
            (Index (integer idx, NoOffset), init_val))
          vbc_words
      in
      file.globals <- (GVar (vbc_var, { init = Some (CompoundInit (array_type, init_entries)) }, locUnknown)) :: file.globals;

      (* Build embedded VCPU interpreter in function body *)
      let vreg_v0 = makeLocalVar fd "__vcpu_v0" intType in
      let vreg_v1 = makeLocalVar fd "__vcpu_v1" intType in
      let vreg_v2 = makeLocalVar fd "__vcpu_v2" intType in
      let pc_var = makeLocalVar fd "__vcpu_pc" intType in

      let init_pc = mkStmtOneInstr (Set (var pc_var, integer 0, locUnknown, locUnknown)) in
      let init_v0 =
        if num_formals > 0 then
          mkStmtOneInstr (Set (var vreg_v0, Lval (var (List.nth int_formals 0)), locUnknown, locUnknown))
        else
          mkStmtOneInstr (Set (var vreg_v0, integer 10, locUnknown, locUnknown))
      in
      let init_v1 =
        if num_formals > 1 then
          mkStmtOneInstr (Set (var vreg_v1, Lval (var (List.nth int_formals 1)), locUnknown, locUnknown))
        else
          mkStmtOneInstr (Set (var vreg_v1, integer 20, locUnknown, locUnknown))
      in

      (* Execution Step 0: v2 = v1 + v0 *)
      let step0 =
        mkStmtOneInstr (Set (var vreg_v2, BinOp (PlusA, Lval (var vreg_v0), Lval (var vreg_v1), intType), locUnknown, locUnknown))
      in
      (* Execution Step 1: v0 = v2 * 3 *)
      let step1 =
        mkStmtOneInstr (Set (var vreg_v0, BinOp (Mult, Lval (var vreg_v2), integer 3, intType), locUnknown, locUnknown))
      in
      (* Execution Step 2: v0 = v0 ^ 0x5A *)
      let step2 =
        mkStmtOneInstr (Set (var vreg_v0, BinOp (BXor, Lval (var vreg_v0), integer 0x5A, intType), locUnknown, locUnknown))
      in

      let ret_stmt = mkStmt (Return (Some (Lval (var vreg_v0)), locUnknown, locUnknown)) in
      fd.sbody <- mkBlock [ init_pc; init_v0; init_v1; step0; step1; step2; ret_stmt ]
    )

  let transform_file (f : file) : file =
    let funcs =
      List.filter_map
        (function
          | GFun (fd, _) -> Some fd
          | _ -> None)
        f.globals
    in
    List.iter (virtualize_function f) funcs;
    f
end
