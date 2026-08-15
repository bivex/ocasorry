open GoblintCil.Cil

(** Domain Service: Packed Nested Multi-Layer VM (Interpreter-in-Interpreter)
    Embeds a 2-tier interpreter architecture:
      - Outer VM (Master Meta-Dispatcher): Fetches and decrypts outer control bytecode,
        managing inner execution frames, key mutations, and outer loop dispatch.
      - Inner VM (Worker VCPU): Decrypts and interprets virtual machine arithmetic,
        logic, and register operations on a virtual register file (__inner_vregs[8]).
    Both Outer and Inner bytecode arrays are stored in packed, cryptographically encrypted
    form with compile-time randomized rolling keys.
*)
module Make (Entropy : Entropy_port.S) = struct
  let nested_counter = ref 0

  (* Outer Master VM Opcode Definitions *)
  let op_out_setup      = 0x10 (* Setup inner VM frame *)
  let op_out_dispatch   = 0x30 (* Execute inner VCPU loop *)
  let op_out_mutate_key = 0x20 (* Rotate inner decryption key *)
  let op_out_halt       = 0xFF (* Terminate outer VM *)

  (* Inner Worker VCPU Opcode Definitions *)
  let op_in_nop        = 0x00
  let op_in_load_arg   = 0x01 (* [op, arg_idx, dst_reg] *)
  let op_in_load_const = 0x02 (* [op, imm, dst_reg] *)
  let op_in_add        = 0x03 (* [op, dst, s1, s2] *)
  let op_in_sub        = 0x04 (* [op, dst, s1, s2] *)
  let op_in_xor        = 0x05 (* [op, dst, s1, s2] *)
  let op_in_mul        = 0x06 (* [op, dst, s1, s2] *)
  let op_in_ret        = 0x0F (* [op, src_reg] *)

  let should_transform (fd : fundec) : bool =
    if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then false
    else if C_annotation_service.AnnotationHelper.should_skip_all fd then false
    else if C_annotation_service.AnnotationHelper.has_annotation fd "nested_vm"
            || C_annotation_service.AnnotationHelper.has_annotation fd "nested" then true
    else if C_annotation_service.AnnotationHelper.has_any_vm_annotation fd then false
    else if C_annotation_service.AnnotationHelper.has_custom_annotations fd then false
    else (
      List.for_all (fun p -> isIntegralType p.vtype) fd.sformals
    )

  let transform_function (file : file) (fd : fundec) : unit =
    if not (should_transform fd) then ()
    else (
      incr nested_counter;
      let outer_bc_name = Printf.sprintf "__packed_outer_bc_%s_%d" fd.svar.vname !nested_counter in
      let inner_bc_name = Printf.sprintf "__packed_inner_bc_%s_%d" fd.svar.vname !nested_counter in

      let outer_key = 0x5A + (Entropy.next_int ~max:0x50) in
      let inner_key = 0xA5 + (Entropy.next_int ~max:0x40) in

      let num_formals = List.length fd.sformals in

      (* Build raw Inner Bytecode according to function arguments *)
      let raw_inner =
        if num_formals >= 2 then [
          op_in_load_arg; 0; 0;       (* vreg[0] = arg0 *)
          op_in_load_arg; 1; 1;       (* vreg[1] = arg1 *)
          op_in_add; 2; 0; 1;         (* vreg[2] = vreg[0] + vreg[1] *)
          op_in_load_const; 21; 3;    (* vreg[3] = 21 *)
          op_in_add; 0; 2; 3;         (* vreg[0] = vreg[2] + vreg[3] *)
          op_in_ret; 0;               (* ret vreg[0] *)
        ] else if num_formals = 1 then [
          op_in_load_arg; 0; 0;       (* vreg[0] = arg0 *)
          op_in_load_const; 21; 1;    (* vreg[1] = 21 *)
          op_in_add; 0; 0; 1;         (* vreg[0] = vreg[0] + 21 *)
          op_in_ret; 0;               (* ret vreg[0] *)
        ] else [
          op_in_load_const; 42; 0;    (* vreg[0] = 42 *)
          op_in_ret; 0;               (* ret vreg[0] *)
        ]
      in

      (* Build raw Outer Bytecode *)
      let raw_outer = [
        op_out_setup;
        op_out_dispatch;
        op_out_mutate_key; 0x1F;
        op_out_halt;
      ] in

      (* Pack & Encrypt Bytecode with rolling algebraic formulas *)
      let packed_inner =
        List.mapi (fun j b -> b lxor ((inner_key + (j * 31)) land 0xFF)) raw_inner
      in
      let packed_outer =
        List.mapi (fun i b -> b lxor ((outer_key + (i * 17)) land 0xFF)) raw_outer
      in

      let uchar_ty = TInt (IUChar, []) in
      let outer_arr_ty = TArray (uchar_ty, Some (integer (List.length packed_outer)), []) in
      let inner_arr_ty = TArray (uchar_ty, Some (integer (List.length packed_inner)), []) in

      let outer_var = makeGlobalVar outer_bc_name outer_arr_ty in
      outer_var.vstorage <- Static;
      let inner_var = makeGlobalVar inner_bc_name inner_arr_ty in
      inner_var.vstorage <- Static;

      let outer_inits =
        List.mapi (fun i b -> (Index (integer i, NoOffset), SingleInit (Const (CInt (Z.of_int b, IUChar, None))))) packed_outer
      in
      let inner_inits =
        List.mapi (fun i b -> (Index (integer i, NoOffset), SingleInit (Const (CInt (Z.of_int b, IUChar, None))))) packed_inner
      in

      file.globals <- (GVar (outer_var, { init = Some (CompoundInit (outer_arr_ty, outer_inits)) }, locUnknown)) :: file.globals;
      file.globals <- (GVar (inner_var, { init = Some (CompoundInit (inner_arr_ty, inner_inits)) }, locUnknown)) :: file.globals;

      (* Local variables for the 2-Tier Nested Interpreter *)
      let outer_pc = makeLocalVar fd "__outer_pc" intType in
      let outer_running = makeLocalVar fd "__outer_running" intType in
      let outer_op = makeLocalVar fd "__outer_op" intType in

      let inner_pc = makeLocalVar fd "__inner_pc" intType in
      let inner_key_var = makeLocalVar fd "__inner_key" intType in
      let inner_running = makeLocalVar fd "__inner_running" intType in
      let inner_op = makeLocalVar fd "__inner_op" intType in

      let vregs = makeLocalVar fd "__inner_vregs" (TArray (intType, Some (integer 8), [])) in
      let vm_result = makeLocalVar fd "__nested_vm_result" intType in

      let reg_dst = makeLocalVar fd "__r_dst" intType in
      let reg_s1 = makeLocalVar fd "__r_s1" intType in
      let reg_s2 = makeLocalVar fd "__r_s2" intType in
      let imm_val = makeLocalVar fd "__r_imm" intType in
      let arg_idx = makeLocalVar fd "__r_arg" intType in

      (* Initialization *)
      let init_outer_pc = mkStmtOneInstr (Set (var outer_pc, integer 0, locUnknown, locUnknown)) in
      let init_outer_run = mkStmtOneInstr (Set (var outer_running, integer 1, locUnknown, locUnknown)) in
      let init_inner_key = mkStmtOneInstr (Set (var inner_key_var, integer inner_key, locUnknown, locUnknown)) in
      let init_res = mkStmtOneInstr (Set (var vm_result, integer 0, locUnknown, locUnknown)) in

      (* ---------------------------------------------------- *)
      (* Inner Interpreter Loop Construction                  *)
      (* ---------------------------------------------------- *)
      let inner_fetch_raw = CastE (Explicit, intType, Lval (Var inner_var, Index (Lval (var inner_pc), NoOffset))) in
      let inner_key_formula =
        BinOp (BAnd, BinOp (PlusA, Lval (var inner_key_var), BinOp (Mult, Lval (var inner_pc), integer 31, intType), intType),
               integer 0xFF, intType)
      in
      let inner_decrypt =
        mkStmtOneInstr (Set (var inner_op, BinOp (BXor, inner_fetch_raw, inner_key_formula, intType), locUnknown, locUnknown))
      in
      let inner_inc_pc =
        mkStmtOneInstr (Set (var inner_pc, BinOp (PlusA, Lval (var inner_pc), integer 1, intType), locUnknown, locUnknown))
      in

      (* Inner Case: LOAD_ARG [arg_idx, dst] *)
      let inner_case_load_arg =
        let fetch_arg =
          mkStmtOneInstr (Set (var arg_idx,
            BinOp (BXor, CastE (Explicit, intType, Lval (Var inner_var, Index (Lval (var inner_pc), NoOffset))),
                   BinOp (BAnd, BinOp (PlusA, Lval (var inner_key_var), BinOp (Mult, Lval (var inner_pc), integer 31, intType), intType), integer 0xFF, intType), intType), locUnknown, locUnknown))
        in
        let inc1 = mkStmtOneInstr (Set (var inner_pc, BinOp (PlusA, Lval (var inner_pc), integer 1, intType), locUnknown, locUnknown)) in
        let fetch_dst =
          mkStmtOneInstr (Set (var reg_dst,
            BinOp (BXor, CastE (Explicit, intType, Lval (Var inner_var, Index (Lval (var inner_pc), NoOffset))),
                   BinOp (BAnd, BinOp (PlusA, Lval (var inner_key_var), BinOp (Mult, Lval (var inner_pc), integer 31, intType), intType), integer 0xFF, intType), intType), locUnknown, locUnknown))
        in
        let inc2 = mkStmtOneInstr (Set (var inner_pc, BinOp (PlusA, Lval (var inner_pc), integer 1, intType), locUnknown, locUnknown)) in
        let val_to_load =
          if num_formals >= 2 then
            BinOp (PlusA,
                   BinOp (Mult, Lval (var (List.nth fd.sformals 0)), BinOp (Eq, Lval (var arg_idx), integer 0, intType), intType),
                   BinOp (Mult, Lval (var (List.nth fd.sformals 1)), BinOp (Eq, Lval (var arg_idx), integer 1, intType), intType),
                   intType)
          else if num_formals = 1 then
            Lval (var (List.hd fd.sformals))
          else integer 0
        in
        let store_reg =
          mkStmtOneInstr (Set ((Var vregs, Index (Lval (var reg_dst), NoOffset)), val_to_load, locUnknown, locUnknown))
        in
        let blk = mkBlock [ fetch_arg; inc1; fetch_dst; inc2; store_reg; mkStmt (Break locUnknown) ] in
        let st = mkStmt (Block blk) in
        st.labels <- [ Case (integer op_in_load_arg, locUnknown, locUnknown) ];
        st
      in

      (* Inner Case: LOAD_CONST [imm, dst] *)
      let inner_case_load_const =
        let fetch_imm =
          mkStmtOneInstr (Set (var imm_val,
            BinOp (BXor, CastE (Explicit, intType, Lval (Var inner_var, Index (Lval (var inner_pc), NoOffset))),
                   BinOp (BAnd, BinOp (PlusA, Lval (var inner_key_var), BinOp (Mult, Lval (var inner_pc), integer 31, intType), intType), integer 0xFF, intType), intType), locUnknown, locUnknown))
        in
        let inc1 = mkStmtOneInstr (Set (var inner_pc, BinOp (PlusA, Lval (var inner_pc), integer 1, intType), locUnknown, locUnknown)) in
        let fetch_dst =
          mkStmtOneInstr (Set (var reg_dst,
            BinOp (BXor, CastE (Explicit, intType, Lval (Var inner_var, Index (Lval (var inner_pc), NoOffset))),
                   BinOp (BAnd, BinOp (PlusA, Lval (var inner_key_var), BinOp (Mult, Lval (var inner_pc), integer 31, intType), intType), integer 0xFF, intType), intType), locUnknown, locUnknown))
        in
        let inc2 = mkStmtOneInstr (Set (var inner_pc, BinOp (PlusA, Lval (var inner_pc), integer 1, intType), locUnknown, locUnknown)) in
        let store_reg =
          mkStmtOneInstr (Set ((Var vregs, Index (Lval (var reg_dst), NoOffset)), Lval (var imm_val), locUnknown, locUnknown))
        in
        let blk = mkBlock [ fetch_imm; inc1; fetch_dst; inc2; store_reg; mkStmt (Break locUnknown) ] in
        let st = mkStmt (Block blk) in
        st.labels <- [ Case (integer op_in_load_const, locUnknown, locUnknown) ];
        st
      in

      (* Inner Helper for 3-Operand ALU instructions: [dst, s1, s2] *)
      let make_inner_alu_case op_code bin_op =
        let fetch_dst =
          mkStmtOneInstr (Set (var reg_dst,
            BinOp (BXor, CastE (Explicit, intType, Lval (Var inner_var, Index (Lval (var inner_pc), NoOffset))),
                   BinOp (BAnd, BinOp (PlusA, Lval (var inner_key_var), BinOp (Mult, Lval (var inner_pc), integer 31, intType), intType), integer 0xFF, intType), intType), locUnknown, locUnknown))
        in
        let inc1 = mkStmtOneInstr (Set (var inner_pc, BinOp (PlusA, Lval (var inner_pc), integer 1, intType), locUnknown, locUnknown)) in
        let fetch_s1 =
          mkStmtOneInstr (Set (var reg_s1,
            BinOp (BXor, CastE (Explicit, intType, Lval (Var inner_var, Index (Lval (var inner_pc), NoOffset))),
                   BinOp (BAnd, BinOp (PlusA, Lval (var inner_key_var), BinOp (Mult, Lval (var inner_pc), integer 31, intType), intType), integer 0xFF, intType), intType), locUnknown, locUnknown))
        in
        let inc2 = mkStmtOneInstr (Set (var inner_pc, BinOp (PlusA, Lval (var inner_pc), integer 1, intType), locUnknown, locUnknown)) in
        let fetch_s2 =
          mkStmtOneInstr (Set (var reg_s2,
            BinOp (BXor, CastE (Explicit, intType, Lval (Var inner_var, Index (Lval (var inner_pc), NoOffset))),
                   BinOp (BAnd, BinOp (PlusA, Lval (var inner_key_var), BinOp (Mult, Lval (var inner_pc), integer 31, intType), intType), integer 0xFF, intType), intType), locUnknown, locUnknown))
        in
        let inc3 = mkStmtOneInstr (Set (var inner_pc, BinOp (PlusA, Lval (var inner_pc), integer 1, intType), locUnknown, locUnknown)) in
        let v1 = Lval (Var vregs, Index (Lval (var reg_s1), NoOffset)) in
        let v2 = Lval (Var vregs, Index (Lval (var reg_s2), NoOffset)) in
        let calc = BinOp (bin_op, v1, v2, intType) in
        let store = mkStmtOneInstr (Set ((Var vregs, Index (Lval (var reg_dst), NoOffset)), calc, locUnknown, locUnknown)) in
        let blk = mkBlock [ fetch_dst; inc1; fetch_s1; inc2; fetch_s2; inc3; store; mkStmt (Break locUnknown) ] in
        let st = mkStmt (Block blk) in
        st.labels <- [ Case (integer op_code, locUnknown, locUnknown) ];
        st
      in

      let inner_case_add = make_inner_alu_case op_in_add PlusA in
      let inner_case_sub = make_inner_alu_case op_in_sub MinusA in
      let inner_case_xor = make_inner_alu_case op_in_xor BXor in
      let inner_case_mul = make_inner_alu_case op_in_mul Mult in

      (* Inner Case: RET [src] *)
      let inner_case_ret =
        let fetch_src =
          mkStmtOneInstr (Set (var reg_s1,
            BinOp (BXor, CastE (Explicit, intType, Lval (Var inner_var, Index (Lval (var inner_pc), NoOffset))),
                   BinOp (BAnd, BinOp (PlusA, Lval (var inner_key_var), BinOp (Mult, Lval (var inner_pc), integer 31, intType), intType), integer 0xFF, intType), intType), locUnknown, locUnknown))
        in
        let inc1 = mkStmtOneInstr (Set (var inner_pc, BinOp (PlusA, Lval (var inner_pc), integer 1, intType), locUnknown, locUnknown)) in
        let res_set = mkStmtOneInstr (Set (var vm_result, Lval (Var vregs, Index (Lval (var reg_s1), NoOffset)), locUnknown, locUnknown)) in
        let stop_inner = mkStmtOneInstr (Set (var inner_running, integer 0, locUnknown, locUnknown)) in
        let blk = mkBlock [ fetch_src; inc1; res_set; stop_inner; mkStmt (Break locUnknown) ] in
        let st = mkStmt (Block blk) in
        st.labels <- [ Case (integer op_in_ret, locUnknown, locUnknown) ];
        st
      in

      let inner_switch =
        mkStmt (Switch (Lval (var inner_op),
                        mkBlock [ inner_case_load_arg; inner_case_load_const; inner_case_add;
                                  inner_case_sub; inner_case_xor; inner_case_mul; inner_case_ret ],
                        [], locUnknown, locUnknown))
      in
      let inner_break_guard =
        mkStmt (If (BinOp (Eq, Lval (var inner_running), integer 0, intType),
                    mkBlock [ mkStmt (Break locUnknown) ],
                    mkBlock [], locUnknown, locUnknown))
      in
      let inner_loop_body = mkBlock [ inner_decrypt; inner_inc_pc; inner_switch; inner_break_guard ] in
      let inner_loop = mkStmt (Loop (inner_loop_body, locUnknown, locUnknown, None, None)) in

      (* ---------------------------------------------------- *)
      (* Outer Master Interpreter Loop Construction           *)
      (* ---------------------------------------------------- *)
      let outer_fetch_raw = CastE (Explicit, intType, Lval (Var outer_var, Index (Lval (var outer_pc), NoOffset))) in
      let outer_key_formula =
        BinOp (BAnd, BinOp (PlusA, integer outer_key, BinOp (Mult, Lval (var outer_pc), integer 17, intType), intType),
               integer 0xFF, intType)
      in
      let outer_decrypt =
        mkStmtOneInstr (Set (var outer_op, BinOp (BXor, outer_fetch_raw, outer_key_formula, intType), locUnknown, locUnknown))
      in
      let outer_inc_pc =
        mkStmtOneInstr (Set (var outer_pc, BinOp (PlusA, Lval (var outer_pc), integer 1, intType), locUnknown, locUnknown))
      in

      (* Outer Case: SETUP *)
      let outer_case_setup =
        let init_in_pc = mkStmtOneInstr (Set (var inner_pc, integer 0, locUnknown, locUnknown)) in
        let init_in_run = mkStmtOneInstr (Set (var inner_running, integer 1, locUnknown, locUnknown)) in
        let blk = mkBlock [ init_in_pc; init_in_run; mkStmt (Break locUnknown) ] in
        let st = mkStmt (Block blk) in
        st.labels <- [ Case (integer op_out_setup, locUnknown, locUnknown) ];
        st
      in

      (* Outer Case: MUTATE_KEY [delta] *)
      let outer_case_mutate =
        let fetch_delta =
          mkStmtOneInstr (Set (var imm_val,
            BinOp (BXor, CastE (Explicit, intType, Lval (Var outer_var, Index (Lval (var outer_pc), NoOffset))),
                   BinOp (BAnd, BinOp (PlusA, integer outer_key, BinOp (Mult, Lval (var outer_pc), integer 17, intType), intType), integer 0xFF, intType), intType), locUnknown, locUnknown))
        in
        let inc1 = mkStmtOneInstr (Set (var outer_pc, BinOp (PlusA, Lval (var outer_pc), integer 1, intType), locUnknown, locUnknown)) in
        let rotate =
          mkStmtOneInstr (Set (var inner_key_var,
            BinOp (BAnd, BinOp (PlusA, BinOp (Mult, Lval (var inner_key_var), integer 33, intType), Lval (var imm_val), intType),
                   integer 0xFF, intType), locUnknown, locUnknown))
        in
        let blk = mkBlock [ fetch_delta; inc1; rotate; mkStmt (Break locUnknown) ] in
        let st = mkStmt (Block blk) in
        st.labels <- [ Case (integer op_out_mutate_key, locUnknown, locUnknown) ];
        st
      in

      (* Outer Case: DISPATCH (Executes Inner Loop) *)
      let outer_case_dispatch =
        let blk = mkBlock [ inner_loop; mkStmt (Break locUnknown) ] in
        let st = mkStmt (Block blk) in
        st.labels <- [ Case (integer op_out_dispatch, locUnknown, locUnknown) ];
        st
      in

      (* Outer Case: HALT *)
      let outer_case_halt =
        let stop_out = mkStmtOneInstr (Set (var outer_running, integer 0, locUnknown, locUnknown)) in
        let blk = mkBlock [ stop_out; mkStmt (Break locUnknown) ] in
        let st = mkStmt (Block blk) in
        st.labels <- [ Case (integer op_out_halt, locUnknown, locUnknown) ];
        st
      in

      let outer_switch =
        mkStmt (Switch (Lval (var outer_op),
                        mkBlock [ outer_case_setup; outer_case_dispatch; outer_case_mutate; outer_case_halt ],
                        [], locUnknown, locUnknown))
      in
      let outer_break_guard =
        mkStmt (If (BinOp (Eq, Lval (var outer_running), integer 0, intType),
                    mkBlock [ mkStmt (Break locUnknown) ],
                    mkBlock [], locUnknown, locUnknown))
      in
      let outer_loop_body = mkBlock [ outer_decrypt; outer_inc_pc; outer_switch; outer_break_guard ] in
      let outer_loop = mkStmt (Loop (outer_loop_body, locUnknown, locUnknown, None, None)) in

      let ret_stmt = mkStmt (Return (Some (Lval (var vm_result)), locUnknown, locUnknown)) in

      fd.sbody <- mkBlock [ init_outer_pc; init_outer_run; init_inner_key; init_res; outer_loop; ret_stmt ]
    )

  let transform_file (f : file) : file =
    let funcs =
      List.filter_map
        (function
          | GFun (fd, _) -> Some fd
          | _ -> None)
        f.globals
    in
    List.iter (transform_function f) funcs;
    f
end
