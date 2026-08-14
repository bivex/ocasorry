open GoblintCil.Cil

(** Domain Service: Dead/Ghost Code Injection with Null-Ring Compensation
    Injects reversible instruction sequences modifying a local variable with
    subsequent algebraic ring compensation:
    v = v + K1; v = v ^ K2; v = v ^ K2; v = v - K1; (Net change = 0)
*)
module Make (Entropy : Entropy_port.S) = struct
  class ghost_code_visitor = object
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
                let k1 = integer 1337 in
                let k2 = integer 0x5A in
                let op1 = Set (dest, BinOp (PlusA, Lval dest, k1, typ), loc, eloc) in
                let op2 = Set (dest, BinOp (BXor, Lval dest, k2, typ), loc, eloc) in
                let op3 = Set (dest, BinOp (BXor, Lval dest, k2, typ), loc, eloc) in
                let op4 = Set (dest, BinOp (MinusA, Lval dest, k1, typ), loc, eloc) in
                let ghost_stmts = [
                  mkStmtOneInstr op1;
                  mkStmtOneInstr op2;
                  mkStmtOneInstr op3;
                  mkStmtOneInstr op4;
                ] in
                new_stmts := List.rev ghost_stmts @ !new_stmts
              )
          | _ -> ())
        b.bstmts;
      b.bstmts <- List.rev !new_stmts;
      DoChildren
  end

  let transform_file (f : file) : file =
    let vis = new ghost_code_visitor in
    visitCilFileSameGlobals vis f;
    f
end
