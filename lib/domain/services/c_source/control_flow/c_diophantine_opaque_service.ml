open GoblintCil.Cil

(** Domain Service: Diophantine Opaque Predicates for CIL AST
    Injects non-trivial opaque predicates based on unsolvable Diophantine equations
    and modular arithmetic theorems:
    - (x * x) % 4 == 2  => Always False (Squares modulo 4 are only 0 or 1)
    - (x * (x + 1) * (x + 2)) % 6 == 0  => Always True (Product of 3 consecutive integers is divisible by 6)
*)
module Make (Entropy : Entropy_port.S) = struct
  class diophantine_visitor = object
    inherit nopCilVisitor

    method! vblock (b : block) : block visitAction =
      let new_stmts = ref [] in
      List.iter
        (fun s ->
          new_stmts := s :: !new_stmts;
          match s.skind with
          | Instr [ Set (dest, _, loc, eloc) ] ->
              let typ = typeOfLval dest in
              if isIntegralType typ then (
                let ik = match typ with TInt (k, _) -> k | _ -> IInt in
                let zero = kinteger64 ik 0L in
                let two = kinteger64 ik 2L in
                let four = kinteger64 ik 4L in
                let six = kinteger64 ik 6L in
                let one = kinteger64 ik 1L in

                (* Predicate: ((x * (x + 1) * (x + 2)) % 6) == 0  => ALWAYS TRUE *)
                let x = Lval dest in
                let x_plus_1 = BinOp (PlusA, x, one, typ) in
                let x_plus_2 = BinOp (PlusA, x, two, typ) in
                let term1 = BinOp (Mult, x, x_plus_1, typ) in
                let term2 = BinOp (Mult, term1, x_plus_2, typ) in
                let mod6 = BinOp (Mod, term2, six, typ) in
                let always_true_cond = BinOp (Eq, mod6, zero, intType) in

                (* False block with unsolvable Diophantine trap: (x^2 % 4 == 2) *)
                let x_sq = BinOp (Mult, x, x, typ) in
                let x_mod4 = BinOp (Mod, x_sq, four, typ) in
                let diophantine_trap = BinOp (Eq, x_mod4, two, intType) in
                let trap_stmt = mkStmtOneInstr (Set (dest, BinOp (PlusA, Lval dest, kinteger64 ik 0xDEADL, typ), loc, eloc)) in

                let trap_if = mkStmt (If (diophantine_trap, mkBlock [ trap_stmt ], mkBlock [], locUnknown, locUnknown)) in
                let opaque_if = mkStmt (If (always_true_cond, mkBlock [], mkBlock [ trap_if ], locUnknown, locUnknown)) in
                new_stmts := opaque_if :: !new_stmts
              )
          | _ -> ())
        b.bstmts;
      b.bstmts <- List.rev !new_stmts;
      DoChildren
  end

  let transform_file (f : file) : file =
    let vis = new diophantine_visitor in
    visitCilFileSameGlobals vis f;
    f
end
