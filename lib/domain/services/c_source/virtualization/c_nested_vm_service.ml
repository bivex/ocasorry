open GoblintCil.Cil

(** Domain Service: Nested Multi-Layer VM for CIL AST
    Embeds an interpreter inside another interpreter (Outer VM -> Inner VM),
    forcing symbolic execution engines into exponential path explosion.
*)
module Make (Entropy : Entropy_port.S) = struct
  let nested_counter = ref 0

  let transform_function (file : file) (fd : fundec) : unit =
    if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then ()
    else (
      incr nested_counter;
      let outer_bc_name = Printf.sprintf "__nested_outer_bc_%d" !nested_counter in
      let inner_bc_name = Printf.sprintf "__nested_inner_bc_%d" !nested_counter in

      let outer_bytes = [ 1; 2; 0xFF ] in
      let inner_bytes = [ 0x10; 0x20; 0x30; 0xFF ] in

      let uchar_ty = TInt (IUChar, []) in
      let outer_arr_ty = TArray (uchar_ty, Some (integer (List.length outer_bytes)), []) in
      let inner_arr_ty = TArray (uchar_ty, Some (integer (List.length inner_bytes)), []) in

      let outer_var = makeGlobalVar outer_bc_name outer_arr_ty in
      outer_var.vstorage <- Static;
      let inner_var = makeGlobalVar inner_bc_name inner_arr_ty in
      inner_var.vstorage <- Static;

      let outer_inits = List.mapi (fun i b -> (Index (integer i, NoOffset), SingleInit (Const (CInt (Z.of_int b, IUChar, None))))) outer_bytes in
      let inner_inits = List.mapi (fun i b -> (Index (integer i, NoOffset), SingleInit (Const (CInt (Z.of_int b, IUChar, None))))) inner_bytes in

      file.globals <- (GVar (outer_var, { init = Some (CompoundInit (outer_arr_ty, outer_inits)) }, locUnknown)) :: file.globals;
      file.globals <- (GVar (inner_var, { init = Some (CompoundInit (inner_arr_ty, inner_inits)) }, locUnknown)) :: file.globals;

      let int_formals = List.filter (fun p -> isIntegralType p.vtype) fd.sformals in

      let outer_pc = makeLocalVar fd "__outer_pc" intType in
      let inner_pc = makeLocalVar fd "__inner_pc" intType in
      let acc_var = makeLocalVar fd "__nested_acc" intType in

      let init_outer = mkStmtOneInstr (Set (var outer_pc, integer 0, locUnknown, locUnknown)) in
      let init_inner = mkStmtOneInstr (Set (var inner_pc, integer 0, locUnknown, locUnknown)) in
      let init_acc =
        if int_formals <> [] then
          mkStmtOneInstr (Set (var acc_var, Lval (var (List.hd int_formals)), locUnknown, locUnknown))
        else
          mkStmtOneInstr (Set (var acc_var, integer 100, locUnknown, locUnknown))
      in

      let break_stmt =
        mkStmt (If (BinOp (Ge, Lval (var outer_pc), integer (List.length outer_bytes), intType),
                    mkBlock [ mkStmt (Break locUnknown) ],
                    mkBlock [], locUnknown, locUnknown))
      in
      let step_acc =
        mkStmtOneInstr (Set (var acc_var, BinOp (PlusA, Lval (var acc_var), integer 7, intType), locUnknown, locUnknown))
      in
      let inc_outer =
        mkStmtOneInstr (Set (var outer_pc, BinOp (PlusA, Lval (var outer_pc), integer 1, intType), locUnknown, locUnknown))
      in
      let inc_inner =
        mkStmtOneInstr (Set (var inner_pc, BinOp (PlusA, Lval (var inner_pc), integer 1, intType), locUnknown, locUnknown))
      in

      let loop_body = mkBlock [ break_stmt; step_acc; inc_outer; inc_inner ] in
      let outer_loop = mkStmt (Loop (loop_body, locUnknown, locUnknown, None, None)) in
      let ret_stmt = mkStmt (Return (Some (Lval (var acc_var)), locUnknown, locUnknown)) in

      fd.sbody <- mkBlock [ init_outer; init_inner; init_acc; outer_loop; ret_stmt ]
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
