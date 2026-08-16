open GoblintCil.Cil

(** Domain Service: Mixed Boolean-Arithmetic (MBA) AST Rewriter for CIL AST *)
module Make (Entropy : Entropy_port.S) = struct
  class mba_visitor = object
    inherit nopCilVisitor

    method! vexpr (e : exp) : exp visitAction =
      match e with
      | BinOp (PlusA, e1, e2, ty) when isIntegralType ty ->
          let variant = Entropy.next_int ~max:5 in
          let new_expr =
            match variant with
            | 0 ->
                (* e1 + e2 = (e1 ^ e2) + ((e1 & e2) << 1) *)
                let xor_part = BinOp (BXor, e1, e2, ty) in
                let and_part = BinOp (BAnd, e1, e2, ty) in
                let shift_part = BinOp (Shiftlt, and_part, integer 1, ty) in
                BinOp (PlusA, xor_part, shift_part, ty)
            | 1 ->
                (* e1 + e2 = (e1 | e2) + (e1 & e2) *)
                let or_part = BinOp (BOr, e1, e2, ty) in
                let and_part = BinOp (BAnd, e1, e2, ty) in
                BinOp (PlusA, or_part, and_part, ty)
            | 2 ->
                (* (x | y) + (x & y)  -- alternative carry form *)
                let or_p = BinOp (BOr, e1, e2, ty) in
                let and_p = BinOp (BAnd, e1, e2, ty) in
                BinOp (PlusA, or_p, and_p, ty)
            | 3 ->
                (* (x & ~y) + (y & ~x) + 2*(x & y) -- uses complement *)
                let nx = UnOp (BNot, e1, ty) in
                let ny = UnOp (BNot, e2, ty) in
                let l = BinOp (BAnd, e1, ny, ty) in
                let r = BinOp (BAnd, e2, nx, ty) in
                let carry2 = BinOp (Shiftlt, BinOp (BAnd, e1, e2, ty), integer 1, ty) in
                BinOp (PlusA, BinOp (PlusA, l, r, ty), carry2, ty)
            | 4 ->
                (* x - ~y - 1  (two's complement identity) *)
                let ny = UnOp (BNot, e2, ty) in
                BinOp (MinusA, BinOp (MinusA, e1, ny, ty), integer 1, ty)
            | _ ->
                (* -(~x | ~y) + (x & y)  *)
                let nx = UnOp (BNot, e1, ty) in
                let ny = UnOp (BNot, e2, ty) in
                let nxory = BinOp (BOr, nx, ny, ty) in
                let neg_nxory = UnOp (Neg, nxory, ty) in
                let andxy = BinOp (BAnd, e1, e2, ty) in
                BinOp (PlusA, neg_nxory, andxy, ty)
          in
          ChangeTo new_expr

      | BinOp (MinusA, e1, e2, ty) when isIntegralType ty ->
          let variant = Entropy.next_int ~max:4 in
          let new_expr =
            match variant with
            | 0 ->
                (* e1 - e2 = (e1 ^ e2) - ((~e1 & e2) << 1) *)
                let xor_part = BinOp (BXor, e1, e2, ty) in
                let not_e1 = UnOp (BNot, e1, ty) in
                let and_part = BinOp (BAnd, not_e1, e2, ty) in
                let shift_part = BinOp (Shiftlt, and_part, integer 1, ty) in
                BinOp (MinusA, xor_part, shift_part, ty)
            | 1 ->
                (* e1 - e2 = (e1 & ~e2) - (~e1 & e2) *)
                let not_e2 = UnOp (BNot, e2, ty) in
                let not_e1 = UnOp (BNot, e1, ty) in
                let left_part = BinOp (BAnd, e1, not_e2, ty) in
                let right_part = BinOp (BAnd, not_e1, e2, ty) in
                BinOp (MinusA, left_part, right_part, ty)
            | 2 ->
                (* x + ~y + 1  (two's complement) *)
                let ny = UnOp (BNot, e2, ty) in
                BinOp (PlusA, BinOp (PlusA, e1, ny, ty), integer 1, ty)
            | 3 ->
                (* ~(~x + y)  *)
                let nx = UnOp (BNot, e1, ty) in
                UnOp (BNot, BinOp (PlusA, nx, e2, ty), ty)
            | _ ->
                (* x XOR y - 2*(~x & y) *)
                let xy = BinOp (BXor, e1, e2, ty) in
                let nx = UnOp (BNot, e1, ty) in
                let nxandy = BinOp (BAnd, nx, e2, ty) in
                let two_nxandy = BinOp (Shiftlt, nxandy, integer 1, ty) in
                BinOp (MinusA, xy, two_nxandy, ty)
          in
          ChangeTo new_expr

      | BinOp (BXor, e1, e2, ty) when isIntegralType ty ->
          let variant = Entropy.next_int ~max:5 in
          let new_expr =
            match variant with
            | 0 ->
                (* e1 ^ e2 = (e1 | e2) - (e1 & e2) *)
                let or_part = BinOp (BOr, e1, e2, ty) in
                let and_part = BinOp (BAnd, e1, e2, ty) in
                BinOp (MinusA, or_part, and_part, ty)
            | 1 ->
                (* e1 ^ e2 = (e1 & ~e2) | (~e1 & e2) *)
                let not_e2 = UnOp (BNot, e2, ty) in
                let not_e1 = UnOp (BNot, e1, ty) in
                let left_part = BinOp (BAnd, e1, not_e2, ty) in
                let right_part = BinOp (BAnd, not_e1, e2, ty) in
                BinOp (BOr, left_part, right_part, ty)
            | 2 ->
                (* x XOR y = (~x & y) | (x & ~y)  *)
                let nx = UnOp (BNot, e1, ty) in
                let ny = UnOp (BNot, e2, ty) in
                BinOp (BOr, BinOp (BAnd, nx, e2, ty), BinOp (BAnd, e1, ny, ty), ty)
            | 3 ->
                (* x XOR y = (x + y) - 2*(x & y)  *)
                let sum = BinOp (PlusA, e1, e2, ty) in
                let and2 = BinOp (Shiftlt, BinOp (BAnd, e1, e2, ty), integer 1, ty) in
                BinOp (MinusA, sum, and2, ty)
            | _ ->
                (* x XOR y = ~( ~(x | y) | ~(~x | ~y) )  -- De Morgan double negation *)
                let nx = UnOp (BNot, e1, ty) in
                let ny = UnOp (BNot, e2, ty) in
                let or1 = UnOp (BNot, BinOp (BOr, e1, e2, ty), ty) in
                let or2 = UnOp (BNot, BinOp (BOr, nx, ny, ty), ty) in
                UnOp (BNot, BinOp (BOr, or1, or2, ty), ty)
          in
          ChangeTo new_expr

      | _ -> DoChildren
  end

  let transform_file (f : file) : file =
    let vis = new mba_visitor in
    visitCilFileSameGlobals (vis :> cilVisitor) f;
    f
end
