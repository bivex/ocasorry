open GoblintCil.Cil

(** Domain Service: High-Order Polynomial MBA & Affine Invertible Transformations over Z_{2^n}
    Generates non-linear polynomial expressions and invertible affine layers:
      y = a^(-1) * ((a * E + b) - b) mod 2^32
    causing combinatorial explosion in symbolic execution solvers (Z3 / angr / Triton).
*)
module Make (Entropy : Entropy_port.S) = struct
  let mod_inv_32 (a : int32) : int32 =
    let a_odd = Int32.logor a 1l in
    let rec iter x steps =
      if steps = 0 then x
      else
        let ax = Int32.mul a_odd x in
        let next_x = Int32.mul x (Int32.sub 2l ax) in
        iter next_x (steps - 1)
    in
    iter 1l 5

  (** Wrap an expression E in an Invertible Affine Layer:
      E' = a_inv * ((a * E + b) - b)
  *)
  let wrap_affine (e : exp) (ty : typ) : exp =
    let raw_a = Int32.of_int (1 + Entropy.next_int ~max:0x7FFF) in
    let a = Int32.logor raw_a 1l in (* ensure gcd(a, 2^32) = 1 *)
    let a_inv = mod_inv_32 a in
    let b = Int32.of_int (Entropy.next_int ~max:0x3FFFFFFF) in

    let exp_a = integer (Int32.to_int a) in
    let exp_a_inv = integer (Int32.to_int a_inv) in
    let exp_b = integer (Int32.to_int b) in

    (* Inner: (a * e) + b *)
    let mul_part = BinOp (Mult, exp_a, e, ty) in
    let affine_inner = BinOp (PlusA, mul_part, exp_b, ty) in
    (* Sub: affine_inner - b *)
    let sub_b = BinOp (MinusA, affine_inner, exp_b, ty) in
    (* Outer: a_inv * (affine_inner - b) *)
    BinOp (Mult, exp_a_inv, sub_b, ty)

  (** Rewrite addition: x + y into 2nd/3rd order Polynomial MBA *)
  let rewrite_poly_add (e1 : exp) (e2 : exp) (ty : typ) : exp =
    let choice = Entropy.next_int ~max:3 in
    match choice with
    | 0 ->
        (* Identity 1: (x ^ y) + 2*(x & y) with Affine wrapping *)
        let xor_part = BinOp (BXor, e1, e2, ty) in
        let and_part = BinOp (BAnd, e1, e2, ty) in
        let shift_and = BinOp (Shiftlt, and_part, integer 1, ty) in
        let sum_part = BinOp (PlusA, xor_part, shift_and, ty) in
        wrap_affine sum_part ty

    | 1 ->
        (* Identity 2: 2*(x | y) - (x ^ y) *)
        let or_part = BinOp (BOr, e1, e2, ty) in
        let double_or = BinOp (Shiftlt, or_part, integer 1, ty) in
        let xor_part = BinOp (BXor, e1, e2, ty) in
        let res = BinOp (MinusA, double_or, xor_part, ty) in
        wrap_affine res ty

    | _ ->
        (* Identity 3: (x | y) + (x & y) *)
        let or_part = BinOp (BOr, e1, e2, ty) in
        let and_part = BinOp (BAnd, e1, e2, ty) in
        let res = BinOp (PlusA, or_part, and_part, ty) in
        wrap_affine res ty

  (** Rewrite subtraction: x - y into Polynomial MBA *)
  let rewrite_poly_sub (e1 : exp) (e2 : exp) (ty : typ) : exp =
    let choice = Entropy.next_int ~max:2 in
    match choice with
    | 0 ->
        (* Identity 1: (x ^ y) - 2*(~x & y) *)
        let xor_part = BinOp (BXor, e1, e2, ty) in
        let not_e1 = UnOp (BNot, e1, ty) in
        let and_part = BinOp (BAnd, not_e1, e2, ty) in
        let double_and = BinOp (Shiftlt, and_part, integer 1, ty) in
        let sub_part = BinOp (MinusA, xor_part, double_and, ty) in
        wrap_affine sub_part ty

    | _ ->
        (* Identity 2: (x & ~y) - (~x & y) *)
        let not_e2 = UnOp (BNot, e2, ty) in
        let left_part = BinOp (BAnd, e1, not_e2, ty) in
        let not_e1 = UnOp (BNot, e1, ty) in
        let right_part = BinOp (BAnd, not_e1, e2, ty) in
        let res = BinOp (MinusA, left_part, right_part, ty) in
        wrap_affine res ty

  (** Rewrite bitwise XOR: x ^ y into Polynomial MBA *)
  let rewrite_poly_xor (e1 : exp) (e2 : exp) (ty : typ) : exp =
    let choice = Entropy.next_int ~max:2 in
    match choice with
    | 0 ->
        (* Identity 1: (x | y) - (x & y) *)
        let or_part = BinOp (BOr, e1, e2, ty) in
        let and_part = BinOp (BAnd, e1, e2, ty) in
        let res = BinOp (MinusA, or_part, and_part, ty) in
        wrap_affine res ty

    | _ ->
        (* Identity 2: (x | y) + (~x & ~y) + 1 *)
        let or_part = BinOp (BOr, e1, e2, ty) in
        let not_e1 = UnOp (BNot, e1, ty) in
        let not_e2 = UnOp (BNot, e2, ty) in
        let and_nots = BinOp (BAnd, not_e1, not_e2, ty) in
        let sum1 = BinOp (PlusA, or_part, and_nots, ty) in
        let res = BinOp (PlusA, sum1, integer 1, ty) in
        wrap_affine res ty

  class poly_mba_visitor = object
    inherit nopCilVisitor

    method! vexpr (e : exp) : exp visitAction =
      match e with
      | BinOp (PlusA, e1, e2, ty) ->
          let transformed = rewrite_poly_add e1 e2 ty in
          ChangeTo transformed

      | BinOp (MinusA, e1, e2, ty) ->
          let transformed = rewrite_poly_sub e1 e2 ty in
          ChangeTo transformed

      | BinOp (BXor, e1, e2, ty) ->
          let transformed = rewrite_poly_xor e1 e2 ty in
          ChangeTo transformed

      | _ -> DoChildren
  end

  let transform_file (f : file) : file =
    let vis = new poly_mba_visitor in
    visitCilFileSameGlobals (vis :> cilVisitor) f;
    f
end
