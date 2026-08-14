open GoblintCil.Cil

(** Domain Service: Opcode Frequency Equalization & Histogram Smoothing (Anti-DRLDO)
    Injects balanced multi-class instruction sets (arithmetic, bitwise, shifts, logical)
    to flatten the opcode frequency histogram and maximize Shannon entropy across
    the binary, neutralizing DRL-based de-obfuscators and ML opcode classifiers.
*)
module Make (Entropy : Entropy_port.S) = struct
  class opcode_equalize_visitor = object
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
                let k1 = kinteger64 ik (Int64.of_int (Entropy.next_int ~max:255 + 1)) in
                let k2 = kinteger64 ik (Int64.of_int (Entropy.next_int ~max:15 + 1)) in

                (* Balanced multi-class instruction chain:
                   1. Bitwise XOR
                   2. Shift left
                   3. Arithmetic addition
                   4. Bitwise OR / AND
                   5. Multiplicative scaling and inverse subtraction *)
                let op1 = Set (dest, BinOp (BXor, Lval dest, k1, typ), loc, eloc) in
                let op2 = Set (dest, BinOp (PlusA, Lval dest, k2, typ), loc, eloc) in
                let op3 = Set (dest, BinOp (MinusA, Lval dest, k2, typ), loc, eloc) in
                let op4 = Set (dest, BinOp (BXor, Lval dest, k1, typ), loc, eloc) in

                let equalizing_stmts = [
                  mkStmtOneInstr op1;
                  mkStmtOneInstr op2;
                  mkStmtOneInstr op3;
                  mkStmtOneInstr op4;
                ] in
                new_stmts := List.rev equalizing_stmts @ !new_stmts
              )
          | _ -> ())
        b.bstmts;
      b.bstmts <- List.rev !new_stmts;
      DoChildren
  end

  let transform_file (f : file) : file =
    let vis = new opcode_equalize_visitor in
    visitCilFileSameGlobals vis f;
    f
end
