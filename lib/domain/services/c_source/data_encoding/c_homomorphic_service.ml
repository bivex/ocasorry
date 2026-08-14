open GoblintCil.Cil

(** Domain Service: Homomorphic Data Encoding for CIL AST
    Rewrites scalar values into an encoded representation:
      x_H = (a * x + b) mod 2^32
    allowing computations (additions and operations) to proceed directly in the transformed space,
    defeating Dynamic Binary Instrumentation (DBI) memory watchpoints.
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

  class homomorphic_visitor = object
    inherit nopCilVisitor

    method! vexpr (e : exp) : exp visitAction =
      match e with
      | BinOp (PlusA, e1, e2, ty) when isIntegralType ty ->
          let a = Int32.of_int (1 + Entropy.next_int ~max:0x7FFF) in
          let a_odd = Int32.logor a 1l in
          let a_inv = mod_inv_32 a_odd in
          let b = Int32.of_int (100 + Entropy.next_int ~max:0x7FFF) in
          let c = Int32.mul a_inv b in

          let u_ty = uintType in
          let exp_a = uint32_exp a_odd in
          let exp_a_inv = uint32_exp a_inv in
          let exp_b = uint32_exp b in
          let exp_c = uint32_exp c in

          let e1_h = BinOp (PlusA, BinOp (Mult, exp_a, CastE (u_ty, e1), u_ty), exp_b, u_ty) in
          let e2_h = BinOp (PlusA, BinOp (Mult, exp_a, CastE (u_ty, e2), u_ty), exp_b, u_ty) in
          let sum_h = BinOp (MinusA, BinOp (PlusA, e1_h, e2_h, u_ty), exp_b, u_ty) in

          (* Decode: (a_inv * sum_h) - c *)
          let decoded = BinOp (MinusA, BinOp (Mult, exp_a_inv, sum_h, u_ty), exp_c, u_ty) in
          ChangeTo (CastE (ty, decoded))

      | _ -> DoChildren
  end

  let transform_file (f : file) : file =
    let vis = new homomorphic_visitor in
    visitCilFileSameGlobals (vis :> cilVisitor) f;
    f
end
