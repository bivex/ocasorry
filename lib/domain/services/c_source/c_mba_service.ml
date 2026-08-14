open GoblintCil.Cil

(** Domain Service: Mixed Boolean-Arithmetic (MBA) AST Rewriter for CIL AST *)
module Make (Entropy : Entropy_port.S) = struct
  class mba_visitor = object
    inherit nopCilVisitor

    method! vexpr (e : exp) : exp visitAction =
      match e with
      | BinOp (PlusA, e1, e2, ty) when isIntegralType ty ->
          let variant = Entropy.next_int ~max:2 in
          let new_expr =
            match variant with
            | 0 ->
                (* e1 + e2 = (e1 ^ e2) + ((e1 & e2) << 1) *)
                let xor_part = BinOp (BXor, e1, e2, ty) in
                let and_part = BinOp (BAnd, e1, e2, ty) in
                let shift_part = BinOp (Shiftlt, and_part, integer 1, ty) in
                BinOp (PlusA, xor_part, shift_part, ty)
            | _ ->
                (* e1 + e2 = (e1 | e2) + (e1 & e2) *)
                let or_part = BinOp (BOr, e1, e2, ty) in
                let and_part = BinOp (BAnd, e1, e2, ty) in
                BinOp (PlusA, or_part, and_part, ty)
          in
          ChangeTo new_expr

      | BinOp (MinusA, e1, e2, ty) when isIntegralType ty ->
          let variant = Entropy.next_int ~max:2 in
          let new_expr =
            match variant with
            | 0 ->
                (* e1 - e2 = (e1 ^ e2) - ((~e1 & e2) << 1) *)
                let xor_part = BinOp (BXor, e1, e2, ty) in
                let not_e1 = UnOp (BNot, e1, ty) in
                let and_part = BinOp (BAnd, not_e1, e2, ty) in
                let shift_part = BinOp (Shiftlt, and_part, integer 1, ty) in
                BinOp (MinusA, xor_part, shift_part, ty)
            | _ ->
                (* e1 - e2 = (e1 & ~e2) - (~e1 & e2) *)
                let not_e2 = UnOp (BNot, e2, ty) in
                let not_e1 = UnOp (BNot, e1, ty) in
                let left_part = BinOp (BAnd, e1, not_e2, ty) in
                let right_part = BinOp (BAnd, not_e1, e2, ty) in
                BinOp (MinusA, left_part, right_part, ty)
          in
          ChangeTo new_expr

      | BinOp (BXor, e1, e2, ty) when isIntegralType ty ->
          let variant = Entropy.next_int ~max:2 in
          let new_expr =
            match variant with
            | 0 ->
                (* e1 ^ e2 = (e1 | e2) - (e1 & e2) *)
                let or_part = BinOp (BOr, e1, e2, ty) in
                let and_part = BinOp (BAnd, e1, e2, ty) in
                BinOp (MinusA, or_part, and_part, ty)
            | _ ->
                (* e1 ^ e2 = (e1 & ~e2) | (~e1 & e2) *)
                let not_e2 = UnOp (BNot, e2, ty) in
                let not_e1 = UnOp (BNot, e1, ty) in
                let left_part = BinOp (BAnd, e1, not_e2, ty) in
                let right_part = BinOp (BAnd, not_e1, e2, ty) in
                BinOp (BOr, left_part, right_part, ty)
          in
          ChangeTo new_expr

      | _ -> DoChildren
  end

  let transform_file (f : file) : file =
    let vis = new mba_visitor in
    visitCilFileSameGlobals (vis :> cilVisitor) f;
    f
end
