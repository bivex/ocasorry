open GoblintCil.Cil

(** Domain Service: Diophantine Opaque Predicates for CIL AST
    Injects non-trivial opaque predicates based on unsolvable Diophantine equations
    and modular arithmetic theorems:
    - (x * x) % 4 == 2  => Always False (Squares modulo 4 are only 0 or 1)
    - (x * (x + 1)) % 2 == 0  => Always True (Product of 2 consecutive integers is always even)
*)
module Make (Entropy : Entropy_port.S) = struct
  class diophantine_visitor = object
    inherit nopCilVisitor

    method! vfunc (fd : fundec) : fundec visitAction =
      if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname
         || C_annotation_service.AnnotationHelper.should_skip_all fd then SkipChildren
      else (
        let rec transform_stmts (stmts : stmt list) : stmt list =
          List.concat_map
            (fun s ->
              match s.skind with
              | Instr [ Set (dest, _, loc, eloc) ] ->
                  let typ = typeOfLval dest in
                  if isIntegralType typ then (
                    let uint_ty = uintType in
                    let x_u = CastE (Explicit, uint_ty, Lval dest) in
                    let one_u = Const (CInt (Z.of_int 1, IUInt, None)) in
                    let two_u = Const (CInt (Z.of_int 2, IUInt, None)) in
                    let four_u = Const (CInt (Z.of_int 4, IUInt, None)) in
                    let zero_u = Const (CInt (Z.of_int 0, IUInt, None)) in

                    (* Predicate: ((x_u * (x_u + 1)) % 2) == 0  => ALWAYS TRUE *)
                    let x_plus_1 = BinOp (PlusA, x_u, one_u, uint_ty) in
                    let prod = BinOp (Mult, x_u, x_plus_1, uint_ty) in
                    let mod2 = BinOp (Mod, prod, two_u, uint_ty) in
                    let always_true_cond = BinOp (Eq, mod2, zero_u, intType) in

                    (* False block with unsolvable Diophantine trap: (x^2 % 4 == 2) *)
                    let x_sq = BinOp (Mult, x_u, x_u, uint_ty) in
                    let x_mod4 = BinOp (Mod, x_sq, four_u, uint_ty) in
                    let diophantine_trap = BinOp (Eq, x_mod4, two_u, intType) in
                    let trap_stmt = mkStmtOneInstr (Set (dest, BinOp (PlusA, Lval dest, integer 0xDEAD, typ), loc, eloc)) in

                    let trap_if = mkStmt (If (diophantine_trap, mkBlock [ trap_stmt ], mkBlock [], locUnknown, locUnknown)) in
                    let opaque_if = mkStmt (If (always_true_cond, mkBlock [], mkBlock [ trap_if ], locUnknown, locUnknown)) in
                    [ s; opaque_if ]
                  ) else [ s ]
              | Block blk ->
                  [ mkStmt (Block { blk with bstmts = transform_stmts blk.bstmts }) ]
              | If (c, tb, fb, l1, l2) ->
                  [ mkStmt (If (c, { tb with bstmts = transform_stmts tb.bstmts },
                                   { fb with bstmts = transform_stmts fb.bstmts }, l1, l2)) ]
              | Loop (blk, l1, l2, b1, b2) ->
                  [ mkStmt (Loop ({ blk with bstmts = transform_stmts blk.bstmts }, l1, l2, b1, b2)) ]
              | _ -> [ s ])
            stmts
        in
        fd.sbody <- { fd.sbody with bstmts = transform_stmts fd.sbody.bstmts };
        SkipChildren
      )
  end

  let transform_file (f : file) : file =
    let vis = new diophantine_visitor in
    visitCilFileSameGlobals vis f;
    f
end
