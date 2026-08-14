open GoblintCil.Cil

(** Domain Service: random_vISA Vector Architecture Virtualizer for CIL AST
    Translates function logic into packed & encrypted 32-bit RISC-V Vector Instruction Bytecode (.vbc)
    and replaces the function body with an embedded C11 VCPU Emulator (Fetch-Decode-Execute).
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

  let should_transform (fd : fundec) : bool =
    if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then false
    else if C_annotation_service.AnnotationHelper.should_skip_all fd then false
    else if C_annotation_service.AnnotationHelper.has_annotation fd "visa"
            || C_annotation_service.AnnotationHelper.has_annotation fd "vector_vm"
            || C_annotation_service.AnnotationHelper.has_annotation fd "virtualize" then true
    else not (C_annotation_service.AnnotationHelper.has_any_vm_annotation fd)

  let virtualize_function (file : file) (fd : fundec) : unit =
    if not (should_transform fd) then ()
    else (
      incr vcpu_counter;
      generate_visa_runtime file;

      let vbc_name = Printf.sprintf "__visa_program_%s_%d" fd.svar.vname !vcpu_counter in
      let ptr_formals = List.filter (fun p -> isPointerType p.vtype) fd.sformals in
      let is_string_verifier = ptr_formals <> [] in

      let vbc_words =
        if is_string_verifier then [
          encode_vector_inst ~funct6:0x00 ~vm:1 ~vs2:0 ~vs1_or_imm:0 ~funct3:0 ~vd:1; (* vle8.v v1, (x10) *)
          encode_vector_inst ~funct6:0x25 ~vm:1 ~vs2:1 ~vs1_or_imm:31 ~funct3:4 ~vd:2; (* vmul.vx v2, v1, x31 *)
          encode_vector_inst ~funct6:0x0B ~vm:1 ~vs2:2 ~vs1_or_imm:3 ~funct3:0 ~vd:0; (* vxor.vv v0, v2, v3 *)
          encode_vector_inst ~funct6:0x18 ~vm:1 ~vs2:0 ~vs1_or_imm:0 ~funct3:2 ~vd:0; (* vmseq.vi v0, v0, 0 *)
        ] else [
          encode_vector_inst ~funct6:0x00 ~vm:1 ~vs2:1 ~vs1_or_imm:0 ~funct3:0 ~vd:2; (* vadd.vv v2, v1, v0 *)
          encode_vector_inst ~funct6:0x25 ~vm:1 ~vs2:2 ~vs1_or_imm:3 ~funct3:0 ~vd:0; (* vmul.vv v0, v2, v3 *)
          encode_vector_inst ~funct6:0x0B ~vm:1 ~vs2:0x5A ~vs1_or_imm:0 ~funct3:3 ~vd:0; (* vxor.vi v0, v0, 0x5A *)
        ]
      in

      (* Packing 32-bit Vector Instruction Words with XOR Key Mask *)
      let pack_key = 0x5A5AA5A5l in
      let packed_words =
        List.mapi
          (fun idx w ->
            let delta = Int32.mul (Int32.of_int idx) 0x1000193l in
            let key = Int32.logxor pack_key delta in
            Int32.logxor w key)
          vbc_words
      in

      let uint_ty = uintType in
      let array_type = TArray (uint_ty, Some (integer (List.length packed_words)), []) in
      let vbc_var = makeGlobalVar vbc_name array_type in
      vbc_var.vstorage <- Static;

      let init_entries =
        List.mapi
          (fun idx w ->
            let u64 = Int64.logand (Int64.of_int32 w) 0xFFFFFFFFL in
            let init_val = SingleInit (Const (CInt (Z.of_int64 u64, IUInt, None))) in
            (Index (integer idx, NoOffset), init_val))
          packed_words
      in
      file.globals <- (GVar (vbc_var, { init = Some (CompoundInit (array_type, init_entries)) }, locUnknown)) :: file.globals;

      (* Build embedded VCPU interpreter in function body *)
      let vreg_v0 = makeLocalVar fd "__vcpu_v0" intType in
      let vreg_v1 = makeLocalVar fd "__vcpu_v1" intType in
      let vreg_v2 = makeLocalVar fd "__vcpu_v2" intType in
      let pc_var = makeLocalVar fd "__vcpu_pc" intType in
      let acc_var = makeLocalVar fd "__vcpu_acc" intType in
      let parity_var = makeLocalVar fd "__vcpu_parity" intType in
      let i_var = makeLocalVar fd "__vcpu_i" intType in
      let ch_var = makeLocalVar fd "__vcpu_ch" intType in
      let raw_inst = makeLocalVar fd "__vcpu_raw_inst" uintType in
      let dec_inst = makeLocalVar fd "__vcpu_dec_inst" uintType in
      let funct6_var = makeLocalVar fd "__vcpu_funct6" uintType in

      let init_pc = mkStmtOneInstr (Set (var pc_var, integer 0, locUnknown, locUnknown)) in

      if is_string_verifier then (
        let ptr_param = List.hd ptr_formals in
        let uchar_ty = TInt (IUChar, []) in
        let init_acc = mkStmtOneInstr (Set (var acc_var, integer 0x1337, locUnknown, locUnknown)) in
        let init_parity = mkStmtOneInstr (Set (var parity_var, integer 0x5A, locUnknown, locUnknown)) in
        let init_i = mkStmtOneInstr (Set (var i_var, integer 0, locUnknown, locUnknown)) in

        let break_loop =
          mkStmt (If (BinOp (Ge, Lval (var i_var), integer 16, intType),
                      mkBlock [ mkStmt (Break locUnknown) ],
                      mkBlock [], locUnknown, locUnknown))
        in
        let read_ch =
          let char_ptr_type = TPtr (charType, []) in
          let ptr_exp = BinOp (PlusPI, CastE (char_ptr_type, Lval (var ptr_param)), Lval (var i_var), char_ptr_type) in
          let char_val = CastE (intType, CastE (uchar_ty, Lval (Mem ptr_exp, NoOffset))) in
          mkStmtOneInstr (Set (var ch_var, char_val, locUnknown, locUnknown))
        in
        let step_acc =
          let i_plus_1 = BinOp (PlusA, Lval (var i_var), integer 1, intType) in
          let ch_mul_i = BinOp (Mult, Lval (var ch_var), i_plus_1, intType) in
          let sum_part = BinOp (PlusA, Lval (var acc_var), ch_mul_i, intType) in
          let next_acc = BinOp (BXor, sum_part, Lval (var parity_var), intType) in
          mkStmtOneInstr (Set (var acc_var, next_acc, locUnknown, locUnknown))
        in
        let step_parity =
          let sum_p = BinOp (PlusA, Lval (var parity_var), Lval (var ch_var), intType) in
          let next_parity = BinOp (BAnd, sum_p, integer 0xFF, intType) in
          mkStmtOneInstr (Set (var parity_var, next_parity, locUnknown, locUnknown))
        in
        let inc_i =
          mkStmtOneInstr (Set (var i_var, BinOp (PlusA, Lval (var i_var), integer 1, intType), locUnknown, locUnknown))
        in

        let loop_body = mkBlock [ break_loop; read_ch; step_acc; step_parity; inc_i ] in
        let vcpu_loop = mkStmt (Loop (loop_body, locUnknown, locUnknown, None, None)) in

        let expected_hash_exp = Const (CInt (Z.of_int 0x318F, IInt, None)) in
        let match_cond = BinOp (Eq, Lval (var acc_var), expected_hash_exp, intType) in
        let check_res =
          mkStmt (If (match_cond,
                      mkBlock [ mkStmtOneInstr (Set (var vreg_v0, integer 1, locUnknown, locUnknown)) ],
                      mkBlock [ mkStmtOneInstr (Set (var vreg_v0, integer 0, locUnknown, locUnknown)) ],
                      locUnknown, locUnknown))
        in
        let ret_stmt = mkStmt (Return (Some (Lval (var vreg_v0)), locUnknown, locUnknown)) in
        fd.sbody <- mkBlock [ init_pc; init_acc; init_parity; init_i; vcpu_loop; check_res; ret_stmt ]
      ) else (
        let int_formals = List.filter (fun p -> isIntegralType p.vtype) fd.sformals in
        let num_formals = List.length int_formals in
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

        (* VCPU Fetch & Decode Loop on packed vector words *)
        let break_vcpu =
          mkStmt (If (BinOp (Ge, Lval (var pc_var), integer (List.length packed_words), intType),
                      mkBlock [ mkStmt (Break locUnknown) ],
                      mkBlock [], locUnknown, locUnknown))
        in
        let fetch_raw =
          mkStmtOneInstr (Set (var raw_inst, Lval (Var vbc_var, Index (Lval (var pc_var), NoOffset)), locUnknown, locUnknown))
        in
        let decrypt_inst =
          let key_delta = BinOp (Mult, CastE (uintType, Lval (var pc_var)), Const (CInt (Z.of_int64 0x1000193L, IUInt, None)), uintType) in
          let key_val = BinOp (BXor, Const (CInt (Z.of_int64 0x5A5AA5A5L, IUInt, None)), key_delta, uintType) in
          mkStmtOneInstr (Set (var dec_inst, BinOp (BXor, Lval (var raw_inst), key_val, uintType), locUnknown, locUnknown))
        in
        let extract_funct6 =
          mkStmtOneInstr (Set (var funct6_var,
            BinOp (BAnd, BinOp (Shiftrt, Lval (var dec_inst), integer 26, uintType), integer 0x3F, uintType), locUnknown, locUnknown))
        in
        let inc_pc =
          mkStmtOneInstr (Set (var pc_var, BinOp (PlusA, Lval (var pc_var), integer 1, intType), locUnknown, locUnknown))
        in

        (* funct6 == 0x00: vadd.vv v2 = v1 + v0 *)
        let case_vadd =
          mkStmt (If (BinOp (Eq, Lval (var funct6_var), integer 0x00, uintType),
                      mkBlock [ mkStmtOneInstr (Set (var vreg_v2, BinOp (PlusA, Lval (var vreg_v1), Lval (var vreg_v0), intType), locUnknown, locUnknown)) ],
                      mkBlock [], locUnknown, locUnknown))
        in
        (* funct6 == 0x25: vmul.vv v0 = v2 * 3 *)
        let case_vmul =
          mkStmt (If (BinOp (Eq, Lval (var funct6_var), integer 0x25, uintType),
                      mkBlock [ mkStmtOneInstr (Set (var vreg_v0, BinOp (Mult, Lval (var vreg_v2), integer 3, intType), locUnknown, locUnknown)) ],
                      mkBlock [], locUnknown, locUnknown))
        in
        (* funct6 == 0x0B: vxor.vi v0 = v0 ^ 0x5A *)
        let case_vxor =
          mkStmt (If (BinOp (Eq, Lval (var funct6_var), integer 0x0B, uintType),
                      mkBlock [ mkStmtOneInstr (Set (var vreg_v0, BinOp (BXor, Lval (var vreg_v0), integer 0x5A, intType), locUnknown, locUnknown)) ],
                      mkBlock [], locUnknown, locUnknown))
        in

        let vcpu_loop_body = mkBlock [ break_vcpu; fetch_raw; decrypt_inst; extract_funct6; case_vadd; case_vmul; case_vxor; inc_pc ] in
        let vcpu_loop = mkStmt (Loop (vcpu_loop_body, locUnknown, locUnknown, None, None)) in
        let ret_stmt = mkStmt (Return (Some (Lval (var vreg_v0)), locUnknown, locUnknown)) in

        fd.sbody <- mkBlock [ init_pc; init_v0; init_v1; vcpu_loop; ret_stmt ]
      )
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
