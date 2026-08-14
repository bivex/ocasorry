open GoblintCil.Cil

(** Domain Service: Dead/Ghost Code Injection with Opcode Blending & Normalization
    Injects diverse reversible instruction sequences (Null-Ring $\sum \Delta \equiv 0$)
    to balance the opcode frequency distribution against ML-based heuristic classifiers (DOOM A-DRL).
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
                let ik = match typ with TInt (k, _) -> k | _ -> IInt in
                let pattern = Entropy.next_int ~max:3 in
                let ghost_stmts =
                  if pattern = 0 then (
                    (* Multi-step Compound Ring: v = ((v + K1) ^ K2) ^ K2 - K1 *)
                    let k1 = kinteger64 ik (Int64.of_int (Entropy.next_int ~max:5000 + 100)) in
                    let k2 = kinteger64 ik (Int64.of_int (Entropy.next_int ~max:255 + 1)) in
                    let op1 = Set (dest, BinOp (PlusA, Lval dest, k1, typ), loc, eloc) in
                    let op2 = Set (dest, BinOp (BXor, Lval dest, k2, typ), loc, eloc) in
                    let op3 = Set (dest, BinOp (BXor, Lval dest, k2, typ), loc, eloc) in
                    let op4 = Set (dest, BinOp (MinusA, Lval dest, k1, typ), loc, eloc) in
                    [ mkStmtOneInstr op1; mkStmtOneInstr op2; mkStmtOneInstr op3; mkStmtOneInstr op4 ]
                  ) else if pattern = 1 then (
                    (* Bitwise Inversion Ring: v = ~(~v) *)
                    let op1 = Set (dest, UnOp (BNot, Lval dest, typ), loc, eloc) in
                    let op2 = Set (dest, UnOp (BNot, Lval dest, typ), loc, eloc) in
                    [ mkStmtOneInstr op1; mkStmtOneInstr op2 ]
                  ) else (
                    (* Linear Scale & Reverse Scale Ring: v = (v - K) + K *)
                    let k = kinteger64 ik (Int64.of_int (Entropy.next_int ~max:1000 + 50)) in
                    let op1 = Set (dest, BinOp (MinusA, Lval dest, k, typ), loc, eloc) in
                    let op2 = Set (dest, BinOp (PlusA, Lval dest, k, typ), loc, eloc) in
                    [ mkStmtOneInstr op1; mkStmtOneInstr op2 ]
                  )
                in
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
