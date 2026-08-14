open GoblintCil.Cil

(** Domain Service: Stochastic Multi-Scheme Instruction Substitution with Opcode Normalization
    Replaces basic arithmetic/logical operations with a randomized selection across
    multiple orthogonal algebraic equivalence classes:
    - Addition:
        1. a - (-b)
        2. (a ^ b) + 2 * (a & b)
        3. (a | b) + (a & b)
    - Subtraction:
        1. a + (-b)
        2. (a ^ b) - 2 * (~a & b)
        3. (a | ~b) - (~a | ~b)
    - Bitwise XOR:
        1. (a | b) - (a & b)
        2. (a & ~b) | (~a & b)
        3. (a | b) & ~(a & b)
    - Increment (x + 1):
        1. -~x
        2. x - (-1)
    - Decrement (x - 1):
        1. ~-x
        2. x + (-1)
*)
module Make (Entropy : Entropy_port.S) = struct
  class subst_visitor = object
    inherit nopCilVisitor

    method! vexpr (e : exp) : exp visitAction =
      match e with
      | BinOp (PlusA, e1, Const (CInt (v, _, _)), typ) when Z.equal v (Z.of_int 1) ->
          let choice = Entropy.next_int ~max:2 in
          if choice = 0 then
            (* x + 1 => -~x *)
            let bnot_e = UnOp (BNot, e1, typ) in
            let neg_e = UnOp (Neg, bnot_e, typ) in
            ChangeTo neg_e
          else
            (* x + 1 => x - (-1) *)
            let minus_one = kinteger64 (match typ with TInt (ik, _) -> ik | _ -> IInt) (-1L) in
            let res = BinOp (MinusA, e1, minus_one, typ) in
            ChangeTo res

      | BinOp (MinusA, e1, Const (CInt (v, _, _)), typ) when Z.equal v (Z.of_int 1) ->
          let choice = Entropy.next_int ~max:2 in
          if choice = 0 then
            (* x - 1 => ~-x *)
            let neg_e = UnOp (Neg, e1, typ) in
            let bnot_e = UnOp (BNot, neg_e, typ) in
            ChangeTo bnot_e
          else
            (* x - 1 => x + (-1) *)
            let minus_one = kinteger64 (match typ with TInt (ik, _) -> ik | _ -> IInt) (-1L) in
            let res = BinOp (PlusA, e1, minus_one, typ) in
            ChangeTo res

      | BinOp (BXor, e1, e2, typ) ->
          let choice = Entropy.next_int ~max:3 in
          if choice = 0 then
            (* x ^ y => (x | y) - (x & y) *)
            let b_or = BinOp (BOr, e1, e2, typ) in
            let b_and = BinOp (BAnd, e1, e2, typ) in
            let res = BinOp (MinusA, b_or, b_and, typ) in
            ChangeTo res
          else if choice = 1 then
            (* x ^ y => (x & ~y) | (~x & y) *)
            let not_e2 = UnOp (BNot, e2, typ) in
            let not_e1 = UnOp (BNot, e1, typ) in
            let term1 = BinOp (BAnd, e1, not_e2, typ) in
            let term2 = BinOp (BAnd, not_e1, e2, typ) in
            let res = BinOp (BOr, term1, term2, typ) in
            ChangeTo res
          else
            (* x ^ y => (x | y) & ~(x & y) *)
            let b_or = BinOp (BOr, e1, e2, typ) in
            let b_and = BinOp (BAnd, e1, e2, typ) in
            let not_and = UnOp (BNot, b_and, typ) in
            let res = BinOp (BAnd, b_or, not_and, typ) in
            ChangeTo res

      | BinOp (PlusA, e1, e2, typ) when not (isConstant e2) ->
          let choice = Entropy.next_int ~max:3 in
          if choice = 0 then
            (* x + y => x - (-y) *)
            let neg_e2 = UnOp (Neg, e2, typ) in
            let res = BinOp (MinusA, e1, neg_e2, typ) in
            ChangeTo res
          else if choice = 1 then
            (* x + y => (x ^ y) + 2 * (x & y) *)
            let xor_term = BinOp (BXor, e1, e2, typ) in
            let and_term = BinOp (BAnd, e1, e2, typ) in
            let two = kinteger64 (match typ with TInt (ik, _) -> ik | _ -> IInt) 2L in
            let mul_and = BinOp (Mult, two, and_term, typ) in
            let res = BinOp (PlusA, xor_term, mul_and, typ) in
            ChangeTo res
          else
            (* x + y => (x | y) + (x & y) *)
            let or_term = BinOp (BOr, e1, e2, typ) in
            let and_term = BinOp (BAnd, e1, e2, typ) in
            let res = BinOp (PlusA, or_term, and_term, typ) in
            ChangeTo res

      | BinOp (MinusA, e1, e2, typ) when not (isConstant e2) ->
          let choice = Entropy.next_int ~max:2 in
          if choice = 0 then
            (* x - y => x + (-y) *)
            let neg_e2 = UnOp (Neg, e2, typ) in
            let res = BinOp (PlusA, e1, neg_e2, typ) in
            ChangeTo res
          else
            (* x - y => (x ^ y) - 2 * (~x & y) *)
            let xor_term = BinOp (BXor, e1, e2, typ) in
            let not_e1 = UnOp (BNot, e1, typ) in
            let not_and = BinOp (BAnd, not_e1, e2, typ) in
            let two = kinteger64 (match typ with TInt (ik, _) -> ik | _ -> IInt) 2L in
            let mul_and = BinOp (Mult, two, not_and, typ) in
            let res = BinOp (MinusA, xor_term, mul_and, typ) in
            ChangeTo res

      | _ -> DoChildren
  end

  let transform_file (f : file) : file =
    let vis = new subst_visitor in
    visitCilFileSameGlobals vis f;
    f
end
