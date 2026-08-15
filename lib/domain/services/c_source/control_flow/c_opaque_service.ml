open GoblintCil.Cil

(** Domain Service: Opaque Predicate Inserter for CIL AST *)
module Make (Entropy : Entropy_port.S) = struct
  class opaque_visitor = object
    inherit nopCilVisitor

    method! vfunc (fd : fundec) : fundec visitAction =
      if fd.svar.vname <> "main" && not (String.starts_with ~prefix:"__" fd.svar.vname) then (
        (* Find an integral formal or create a local integer variable *)
        let int_var =
          match List.find_opt (fun p -> isIntegralType p.vtype) fd.sformals with
          | Some p -> p
          | None -> (
              match List.find_opt (fun l -> isIntegralType l.vtype && not (String.starts_with ~prefix:"__" l.vname)) fd.slocals with
              | Some l -> l
              | None -> makeLocalVar fd "__opaque_v" intType
            )
        in
        let var_exp = Lval (var int_var) in
        let var_ty = int_var.vtype in

        (* Invariant: (param & ~param) != 0 -> always false *)
        let not_var = UnOp (BNot, var_exp, var_ty) in
        let and_expr = BinOp (BAnd, var_exp, not_var, var_ty) in
        let cond_exp = BinOp (Ne, and_expr, integer 0, intType) in

        (* Dead block with dead computation / assignment *)
        let junk_instr =
          Set (var int_var, integer (Entropy.next_int ~max:0x7FFF), locUnknown, locUnknown)
        in
        let dead_stmt = mkStmtOneInstr junk_instr in
        let dead_block = mkBlock [ dead_stmt ] in
        let empty_block = mkBlock [] in

        let opaque_if_stmt =
          mkStmt (If (cond_exp, dead_block, empty_block, locUnknown, locUnknown))
        in
        fd.sbody <- { fd.sbody with bstmts = opaque_if_stmt :: fd.sbody.bstmts }
      );
      DoChildren
  end

  let transform_file (f : file) : file =
    let vis = new opaque_visitor in
    visitCilFileSameGlobals vis f;
    f
end
