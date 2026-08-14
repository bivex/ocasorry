open GoblintCil.Cil

(** Domain Service: Floating-Point Mixed Boolean-Arithmetic (FLOB Lifting)
    Lifts IEEE-754 floating-point operations (float, double) into a scaled integer
    fixed-point domain with exact binary expansion:
      x_lifted = (int64_t)(x * SCALE)
      y_lifted = (int64_t)(y * SCALE)
    Applies non-trivial MBA transformations in the lifted domain:
      (x + y)_lifted = (x_lifted ^ y_lifted) + 2 * (x_lifted & y_lifted)
      (x - y)_lifted = (x_lifted ^ y_lifted) - 2 * (~x_lifted & y_lifted)
    and projects back into IEEE-754 space:
      res = ((double)res_lifted) / SCALE
    protecting DNN & mathematical computations from dynamic extraction and reverse engineering.
*)
module Make (Entropy : Entropy_port.S) = struct
  let is_floating_type (ty : typ) : bool =
    match unrollType ty with
    | TFloat _ -> true
    | _ -> false

  let scale_factor = 65536.0 (* 2^16 scaling *)

  class float_mba_visitor = object
    inherit nopCilVisitor

    method! vexpr (e : exp) : exp visitAction =
      match e with
      | BinOp (PlusA, e1, e2, ty) when is_floating_type ty ->
          let fk = match unrollType ty with TFloat (k, _) -> k | _ -> FDouble in
          let scale_const = Const (CReal (scale_factor, fk, None)) in
          let i64_typ = TInt (ILongLong, []) in

          let e1_scaled = BinOp (Mult, e1, scale_const, ty) in
          let e2_scaled = BinOp (Mult, e2, scale_const, ty) in
          let e1_lifted = CastE (i64_typ, e1_scaled) in
          let e2_lifted = CastE (i64_typ, e2_scaled) in

          (* MBA addition: (a ^ b) + 2 * (a & b) *)
          let xor_part = BinOp (BXor, e1_lifted, e2_lifted, i64_typ) in
          let and_part = BinOp (BAnd, e1_lifted, e2_lifted, i64_typ) in
          let two = kinteger64 ILongLong 2L in
          let two_and = BinOp (Mult, two, and_part, i64_typ) in
          let sum_lifted = BinOp (PlusA, xor_part, two_and, i64_typ) in

          let sum_float = CastE (ty, sum_lifted) in
          let result = BinOp (Div, sum_float, scale_const, ty) in
          ChangeTo result

      | BinOp (MinusA, e1, e2, ty) when is_floating_type ty ->
          let fk = match unrollType ty with TFloat (k, _) -> k | _ -> FDouble in
          let scale_const = Const (CReal (scale_factor, fk, None)) in
          let i64_typ = TInt (ILongLong, []) in

          let e1_scaled = BinOp (Mult, e1, scale_const, ty) in
          let e2_scaled = BinOp (Mult, e2, scale_const, ty) in
          let e1_lifted = CastE (i64_typ, e1_scaled) in
          let e2_lifted = CastE (i64_typ, e2_scaled) in

          (* MBA subtraction: (a ^ b) - 2 * (~a & b) *)
          let xor_part = BinOp (BXor, e1_lifted, e2_lifted, i64_typ) in
          let not_e1 = UnOp (BNot, e1_lifted, i64_typ) in
          let not_and = BinOp (BAnd, not_e1, e2_lifted, i64_typ) in
          let two = kinteger64 ILongLong 2L in
          let two_and = BinOp (Mult, two, not_and, i64_typ) in
          let diff_lifted = BinOp (MinusA, xor_part, two_and, i64_typ) in

          let diff_float = CastE (ty, diff_lifted) in
          let result = BinOp (Div, diff_float, scale_const, ty) in
          ChangeTo result

      | _ -> DoChildren
  end

  let transform_file (f : file) : file =
    let vis = new float_mba_visitor in
    visitCilFileSameGlobals (vis :> cilVisitor) f;
    f
end
