open GoblintCil.Cil

(** Domain Service: Opaque Predicate Inserter for CIL AST *)
module Make (Entropy : Entropy_port.S) = struct
  class opaque_visitor = object
    inherit nopCilVisitor

    method! vfunc (fd : fundec) : fundec visitAction =
      if List.length fd.sformals > 0 then (
        let first_param = List.hd fd.sformals in
        let var_exp = Lval (var first_param) in
        let var_ty = first_param.vtype in

        (* Invariant: (param & ~param) != 0 -> always false *)
        let not_var = UnOp (BNot, var_exp, var_ty) in
        let and_expr = BinOp (BAnd, var_exp, not_var, var_ty) in
        let cond_exp = BinOp (Ne, and_expr, integer 0, intType) in

        (* Dead block with dead computation / assignment *)
        let junk_instr =
          Set (var first_param, integer (Entropy.next_int ~max:0xFFFF), locUnknown, locUnknown)
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
