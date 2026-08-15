open GoblintCil.Cil

(** Domain Service: High-Order Polynomial MBA & Affine Invertible Transformations over Z_{2^n}
    Generates non-linear polynomial expressions and invertible affine layers:
      T = (a * E + b) mod 2^32
      E' = (a^(-1) * T) - (a^(-1) * b) mod 2^32
    using unsigned integer arithmetic for well-defined modular wrapping without precedence ambiguities.
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

  let uint32_exp (v : int32) : exp =
    let u64 = Int64.logand (Int64.of_int32 v) 0xFFFFFFFFL in
    Const (CInt (Z.of_int64 u64, IUInt, None))

  (** Wrap an expression E in an Invertible Affine Layer:
      E' = (ty)( (a_inv * (a * E + b)) - (a_inv * b) )
  *)
  let wrap_affine (e : exp) (ty : typ) : exp =
    let raw_a = Int32.of_int (1 + Entropy.next_int ~max:0x7FFF) in
    let a = Int32.logor raw_a 1l in (* ensure gcd(a, 2^32) = 1 *)
    let a_inv = mod_inv_32 a in
    let b = Int32.of_int (Entropy.next_int ~max:0x3FFFFFFF) in
    let c = Int32.mul a_inv b in (* constant = a_inv * b mod 2^32 *)

    let u_ty = uintType in
    let exp_a = uint32_exp a in
    let exp_a_inv = uint32_exp a_inv in
    let exp_b = uint32_exp b in
    let exp_c = uint32_exp c in
    let e_cast = CastE (Explicit, u_ty, e) in

    (* Forward: T = (a * e) + b *)
    let mul_part = BinOp (Mult, exp_a, e_cast, u_ty) in
    let affine_inner = BinOp (PlusA, mul_part, exp_b, u_ty) in

    (* Inverse: (a_inv * T) - c *)
    let scaled_t = BinOp (Mult, exp_a_inv, affine_inner, u_ty) in
    let recovered = BinOp (MinusA, scaled_t, exp_c, u_ty) in
    CastE (Explicit, ty, recovered)

  (** Rewrite addition: x + y into 2nd/3rd order Polynomial MBA *)
  let rewrite_poly_add (e1 : exp) (e2 : exp) (ty : typ) : exp =
    let choice = Entropy.next_int ~max:2 in
    match choice with
    | 0 ->
        (* Identity 1: (x ^ y) + 2*(x & y) with Affine wrapping *)
        let xor_part = BinOp (BXor, e1, e2, ty) in
        let and_part = BinOp (BAnd, e1, e2, ty) in
        let shift_and = BinOp (Shiftlt, and_part, integer 1, ty) in
        let sum_part = BinOp (PlusA, xor_part, shift_and, ty) in
        wrap_affine sum_part ty

    | _ ->
        (* Identity 2: (x | y) + (x & y) with Affine wrapping *)
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
        (* Identity 2: (x & ~y) | (~x & y) *)
        let not_e1 = UnOp (BNot, e1, ty) in
        let not_e2 = UnOp (BNot, e2, ty) in
        let left_part = BinOp (BAnd, e1, not_e2, ty) in
        let right_part = BinOp (BAnd, not_e1, e2, ty) in
        let res = BinOp (BOr, left_part, right_part, ty) in
        wrap_affine res ty

  class poly_mba_visitor = object
    inherit nopCilVisitor

    method! vexpr (e : exp) : exp visitAction =
      match e with
      | BinOp (PlusA, e1, e2, ty) when isIntegralType ty ->
          let transformed = rewrite_poly_add e1 e2 ty in
          ChangeTo transformed

      | BinOp (MinusA, e1, e2, ty) when isIntegralType ty ->
          let transformed = rewrite_poly_sub e1 e2 ty in
          ChangeTo transformed

      | BinOp (BXor, e1, e2, ty) when isIntegralType ty ->
          let transformed = rewrite_poly_xor e1 e2 ty in
          ChangeTo transformed

      | _ -> DoChildren
  end

  let transform_file (f : file) : file =
    let vis = new poly_mba_visitor in
    visitCilFileSameGlobals (vis :> cilVisitor) f;
    f
end
