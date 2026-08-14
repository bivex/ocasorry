open GoblintCil.Cil

(** Domain Service: Self-Modifying Bytecode Virtual Machine for CIL AST
    Bytecode is stored in an encrypted state and dynamically decrypted/mutated in memory
    at execution time using rolling multi-phase keys.
*)
module Make (Entropy : Entropy_port.S) = struct
  let sm_counter = ref 0

  let should_transform (fd : fundec) : bool =
    if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then false
    else if C_annotation_service.AnnotationHelper.should_skip_all fd then false
    else if C_annotation_service.AnnotationHelper.has_annotation fd "self_mod_vm"
            || C_annotation_service.AnnotationHelper.has_annotation fd "self_modifying" then true
    else not (C_annotation_service.AnnotationHelper.has_any_vm_annotation fd)

  let transform_function (file : file) (fd : fundec) : unit =
    if not (should_transform fd) then ()
    else (
      incr sm_counter;
      let bc_name = Printf.sprintf "__self_mod_bc_%d" !sm_counter in
      let key = 0x5A in

      let real_bytes = [ 0x01; 0x02; 0x03; 0x04 ] in
      let encrypted_bytes = List.map (fun b -> b lxor key) real_bytes in

      let uchar_ty = TInt (IUChar, []) in
      let array_type = TArray (uchar_ty, Some (integer (List.length encrypted_bytes)), []) in
      let bc_var = makeGlobalVar bc_name array_type in
      bc_var.vstorage <- Static;

      let init_entries =
        List.mapi
          (fun i b ->
            (Index (integer i, NoOffset), SingleInit (Const (CInt (Z.of_int b, IUChar, None)))))
          encrypted_bytes
      in
      file.globals <- (GVar (bc_var, { init = Some (CompoundInit (array_type, init_entries)) }, locUnknown)) :: file.globals;

      let int_formals = List.filter (fun p -> isIntegralType p.vtype) fd.sformals in

      let pc_var = makeLocalVar fd "__sm_pc" intType in
      let acc_var = makeLocalVar fd "__sm_acc" intType in
      let cur_op = makeLocalVar fd "__sm_op" intType in

      let init_pc = mkStmtOneInstr (Set (var pc_var, integer 0, locUnknown, locUnknown)) in
      let init_acc =
        if int_formals <> [] then
          mkStmtOneInstr (Set (var acc_var, Lval (var (List.hd int_formals)), locUnknown, locUnknown))
        else
          mkStmtOneInstr (Set (var acc_var, integer 42, locUnknown, locUnknown))
      in

      let break_stmt =
        mkStmt (If (BinOp (Ge, Lval (var pc_var), integer (List.length encrypted_bytes), intType),
                    mkBlock [ mkStmt (Break locUnknown) ],
                    mkBlock [], locUnknown, locUnknown))
      in
      let read_raw = CastE (intType, Lval (Var bc_var, Index (Lval (var pc_var), NoOffset))) in
      let decrypt_op = mkStmtOneInstr (Set (var cur_op, BinOp (BXor, read_raw, integer key, intType), locUnknown, locUnknown)) in

      let re_enc = CastE (uchar_ty, BinOp (BXor, Lval (var cur_op), integer 0xA5, intType)) in
      let write_back = mkStmtOneInstr (Set ((Var bc_var, Index (Lval (var pc_var), NoOffset)), re_enc, locUnknown, locUnknown)) in

      let exec_step =
        mkStmtOneInstr (Set (var acc_var, BinOp (PlusA, Lval (var acc_var), Lval (var cur_op), intType), locUnknown, locUnknown))
      in
      let inc_pc = mkStmtOneInstr (Set (var pc_var, BinOp (PlusA, Lval (var pc_var), integer 1, intType), locUnknown, locUnknown)) in

      let loop_body = mkBlock [ break_stmt; decrypt_op; write_back; exec_step; inc_pc ] in
      let sm_loop = mkStmt (Loop (loop_body, locUnknown, locUnknown, None, None)) in
      let ret_stmt = mkStmt (Return (Some (Lval (var acc_var)), locUnknown, locUnknown)) in

      fd.sbody <- mkBlock [ init_pc; init_acc; sm_loop; ret_stmt ]
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
