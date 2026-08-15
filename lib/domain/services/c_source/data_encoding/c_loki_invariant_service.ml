open GoblintCil.Cil

(** Domain Service: Polynomial Algebraic Invariant Constant Folding (Loki MBA Invariants)
    Based on Loki (arXiv:2106.08913).
    Replaces integer constants C with dynamic polynomial identities over Z/2^32Z:
      P(x, y) = 0 mod 2^32  =>  C = C + P(x, y)
    Guarantees exact semantic equivalence while destroying static constant folding in -O2/-O3
    and causing SAT solver timeouts in automated symbolic deobfuscators.
*)
module Make (Entropy : Entropy_port.S) = struct
  let should_transform (fd : fundec) : bool =
    if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then false
    else if C_annotation_service.AnnotationHelper.should_skip_all fd then false
    else true

  (** Helper: Multiplicative inverse in Z_{2^32} *)
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

  (** Synthesize a null polynomial P(x, y) = 0 mod 2^32 *)
  let synthesize_null_poly (e_x : exp) (e_y : exp) (_ty : typ) : exp =
    let u32_ty = uintType in
    let x_u = CastE (Explicit, u32_ty, e_x) in
    let y_u = CastE (Explicit, u32_ty, e_y) in
    let rand_k = Int64.of_int (1 + Entropy.next_int ~max:0x3FFFFFFF) in
    let k_exp = Const (CInt (Z.of_int64 rand_k, IUInt, None)) in

    let choice = Entropy.next_int ~max:4 in
    match choice with
    | 0 ->
        (* Form 1: P(x) = (x * (x + 1) * (x + 2) * (x + 3)) * 2^29 == 0 mod 2^32 *)
        let one = Const (CInt (Z.one, IUInt, None)) in
        let two = Const (CInt (Z.of_int 2, IUInt, None)) in
        let three = Const (CInt (Z.of_int 3, IUInt, None)) in
        let shift29 = Const (CInt (Z.of_int64 0x20000000L, IUInt, None)) in
        let x1 = BinOp (PlusA, x_u, one, u32_ty) in
        let x2 = BinOp (PlusA, x_u, two, u32_ty) in
        let x3 = BinOp (PlusA, x_u, three, u32_ty) in
        let p_a = BinOp (Mult, x_u, x1, u32_ty) in
        let p_b = BinOp (Mult, x2, x3, u32_ty) in
        let p_all = BinOp (Mult, p_a, p_b, u32_ty) in
        BinOp (Mult, p_all, shift29, u32_ty)

    | 1 ->
        (* Form 2: P(x, y) = ((x | y) - (x & y) - (x ^ y)) * K == 0 mod 2^32 *)
        let or_part = BinOp (BOr, x_u, y_u, u32_ty) in
        let and_part = BinOp (BAnd, x_u, y_u, u32_ty) in
        let xor_part = BinOp (BXor, x_u, y_u, u32_ty) in
        let diff1 = BinOp (MinusA, or_part, and_part, u32_ty) in
        let diff2 = BinOp (MinusA, diff1, xor_part, u32_ty) in
        BinOp (Mult, diff2, k_exp, u32_ty)

    | 2 ->
        (* Form 3: P(x, y) = ((x ^ y) + 2*(x & y) - (x + y)) * K == 0 mod 2^32 *)
        let xor_part = BinOp (BXor, x_u, y_u, u32_ty) in
        let and_part = BinOp (BAnd, x_u, y_u, u32_ty) in
        let two = Const (CInt (Z.of_int 2, IUInt, None)) in
        let double_and = BinOp (Mult, and_part, two, u32_ty) in
        let sum_xor_and = BinOp (PlusA, xor_part, double_and, u32_ty) in
        let sum_xy = BinOp (PlusA, x_u, y_u, u32_ty) in
        let diff = BinOp (MinusA, sum_xor_and, sum_xy, u32_ty) in
        BinOp (Mult, diff, k_exp, u32_ty)

    | _ ->
        (* Form 4: P(x, y) = ((x & ~y) + (~x & y) - (x ^ y)) * K == 0 mod 2^32 *)
        let not_y = UnOp (BNot, y_u, u32_ty) in
        let not_x = UnOp (BNot, x_u, u32_ty) in
        let x_and_ny = BinOp (BAnd, x_u, not_y, u32_ty) in
        let nx_and_y = BinOp (BAnd, not_x, y_u, u32_ty) in
        let sum_parts = BinOp (PlusA, x_and_ny, nx_and_y, u32_ty) in
        let xor_part = BinOp (BXor, x_u, y_u, u32_ty) in
        let diff = BinOp (MinusA, sum_parts, xor_part, u32_ty) in
        BinOp (Mult, diff, k_exp, u32_ty)

  class loki_visitor ~(global_enabled : bool) (fd : fundec) = object
    inherit nopCilVisitor

    val mutable current_fn_enabled = false
    val live_vars =
      List.filter (fun v -> isIntegralType v.vtype) fd.sformals

    initializer
      current_fn_enabled <-
        (global_enabled && not (C_annotation_service.AnnotationHelper.has_any_vm_annotation fd)) ||
        C_annotation_service.AnnotationHelper.has_annotation fd "loki_invariant" ||
        C_annotation_service.AnnotationHelper.has_annotation fd "loki" ||
        C_annotation_service.AnnotationHelper.has_annotation fd "poly_invariant" ||
        C_annotation_service.AnnotationHelper.has_annotation fd "null_poly"

    method! vexpr (e : exp) : exp visitAction =
      if not current_fn_enabled || live_vars = [] then DoChildren
      else match e with
      | Const (CInt (v, _ik, _)) when (Z.abs v > Z.of_int 2) && isIntegralType (typeOf e) ->
          let choice = Entropy.next_int ~max:10 in
          if choice < 6 then (
            let ty = typeOf e in
            let var_count = List.length live_vars in
            let v1 = List.nth live_vars (Entropy.next_int ~max:var_count) in
            let v2 = List.nth live_vars (Entropy.next_int ~max:var_count) in
            let e1 = Lval (var v1) in
            let e2 = Lval (var v2) in
            let null_p = synthesize_null_poly e1 e2 ty in
            let c_cast = CastE (Explicit, uintType, e) in
            let sum_c_p = BinOp (PlusA, c_cast, null_p, uintType) in
            ChangeTo (CastE (Explicit, ty, sum_c_p))
          ) else DoChildren

      | _ -> DoChildren
  end

  let transform_file ?(global : bool = true) (f : file) : file =
    let funcs =
      List.filter_map
        (function
          | GFun (fd, _) when should_transform fd -> Some fd
          | _ -> None)
        f.globals
    in
    List.iter
      (fun fd ->
        let vis = new loki_visitor ~global_enabled:global fd in
        ignore (visitCilFunction (vis :> cilVisitor) fd)
      ) funcs;
    f
end
