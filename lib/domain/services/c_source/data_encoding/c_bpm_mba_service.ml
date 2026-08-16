open GoblintCil.Cil

(** Domain Service: Bit-Permutation Mixed Boolean-Arithmetic (BPM)
    Implements advanced BPM transformations (SSRN 2025 / Anti-DSE):
      Interleaves bitwise permutation networks pi(x) and pi^{-1}(x) with
      non-linear modular arithmetic rings over Z_{2^32}.

      Mathematical Invariant:
        pi(x ^ y) == pi(x) ^ pi(y)
        pi(x & y) == pi(x) & pi(y)
        pi(x | y) == pi(x) | pi(y)

      Transformation Identities:
        x ^ y === pi^{-1}( (pi(x) | pi(y)) - (pi(x) & pi(y)) )
        x & y === pi^{-1}( (pi(x) | pi(y)) - (pi(x) ^ pi(y)) )
        x | y === pi^{-1}( (pi(x) ^ pi(y)) + (pi(x) & pi(y)) )
        x + y === pi^{-1}(pi(x) ^ pi(y)) + (pi^{-1}(pi(x) & pi(y)) << 1)

      Forces SMT solvers (Z3, Bitwuzla) into exponential bit-blasting complexity.
*)

module Make (Entropy : Entropy_port.S) = struct

  type butterfly_stage = {
    mask  : int64;
    shift : int;
  }

  let stages = [|
    { mask = 0x55555555L; shift = 1 };
    { mask = 0x33333333L; shift = 2 };
    { mask = 0x0F0F0F0FL; shift = 4 };
    { mask = 0x00FF00FFL; shift = 8 };
    { mask = 0x0000FFFFL; shift = 16 };
  |]

  let u32_const (v : int64) : exp =
    Const (CInt (Z.of_int64 (Int64.logand v 0xFFFFFFFFL), IUInt, None))

  (** Apply single butterfly permutation stage to AST expression *)
  let apply_stage (e : exp) (stg : butterfly_stage) (ty : typ) : exp =
    let u_ty = uintType in
    let e_u = CastE (Explicit, u_ty, e) in
    let m_exp = u32_const stg.mask in
    let s_exp = integer stg.shift in
    (* t = ((e >> s) ^ e) & mask *)
    let sh_r = BinOp (Shiftrt, e_u, s_exp, u_ty) in
    let xor1 = BinOp (BXor, sh_r, e_u, u_ty) in
    let t    = BinOp (BAnd, xor1, m_exp, u_ty) in
    (* res = e ^ (t << s) ^ t *)
    let t_sh = BinOp (Shiftlt, t, s_exp, u_ty) in
    let xor2 = BinOp (BXor, e_u, t_sh, u_ty) in
    let res  = BinOp (BXor, xor2, t, u_ty) in
    CastE (Explicit, ty, res)

  (** Generate a randomized bit-permutation pipeline *)
  let make_random_permutation () =
    let count = 1 + Entropy.next_int ~max:3 in
    let picked = ref [] in
    for _ = 1 to count do
      let idx = Entropy.next_int ~max:(Array.length stages) in
      picked := stages.(idx) :: !picked
    done;
    !picked

  (** Forward permutation pi(x) *)
  let apply_perm (stgs : butterfly_stage list) (e : exp) (ty : typ) : exp =
    List.fold_left (fun acc stg -> apply_stage acc stg ty) e stgs

  (** Inverse permutation pi^{-1}(x) (butterfly stages in reverse) *)
  let apply_inv_perm (stgs : butterfly_stage list) (e : exp) (ty : typ) : exp =
    List.fold_left (fun acc stg -> apply_stage acc stg ty) e (List.rev stgs)

  class bpm_visitor = object
    inherit nopCilVisitor

    method! vexpr (e : exp) : exp visitAction =
      match e with
      | BinOp (BXor, e1, e2, ty) when isIntegralType ty ->
          if Entropy.next_int ~max:100 < 60 then (
            let perm = make_random_permutation () in
            let p1 = apply_perm perm e1 ty in
            let p2 = apply_perm perm e2 ty in
            (* pi(x) | pi(y) *)
            let or_part = BinOp (BOr, p1, p2, ty) in
            (* pi(x) & pi(y) *)
            let and_part = BinOp (BAnd, p1, p2, ty) in
            (* (pi(x) | pi(y)) - (pi(x) & pi(y)) *)
            let sub_part = BinOp (MinusA, or_part, and_part, ty) in
            (* pi^{-1}( ... ) *)
            let res = apply_inv_perm perm sub_part ty in
            ChangeTo res
          ) else DoChildren

      | BinOp (BAnd, e1, e2, ty) when isIntegralType ty ->
          if Entropy.next_int ~max:100 < 50 then (
            let perm = make_random_permutation () in
            let p1 = apply_perm perm e1 ty in
            let p2 = apply_perm perm e2 ty in
            let or_part  = BinOp (BOr, p1, p2, ty) in
            let xor_part = BinOp (BXor, p1, p2, ty) in
            let sub_part = BinOp (MinusA, or_part, xor_part, ty) in
            let res = apply_inv_perm perm sub_part ty in
            ChangeTo res
          ) else DoChildren

      | BinOp (BOr, e1, e2, ty) when isIntegralType ty ->
          if Entropy.next_int ~max:100 < 50 then (
            let perm = make_random_permutation () in
            let p1 = apply_perm perm e1 ty in
            let p2 = apply_perm perm e2 ty in
            let xor_part = BinOp (BXor, p1, p2, ty) in
            let and_part = BinOp (BAnd, p1, p2, ty) in
            let add_part = BinOp (PlusA, xor_part, and_part, ty) in
            let res = apply_inv_perm perm add_part ty in
            ChangeTo res
          ) else DoChildren

      | BinOp (PlusA, e1, e2, ty) when isIntegralType ty ->
          if Entropy.next_int ~max:100 < 45 then (
            let perm = make_random_permutation () in
            let p1 = apply_perm perm e1 ty in
            let p2 = apply_perm perm e2 ty in
            let xor_part = BinOp (BXor, p1, p2, ty) in
            let and_part = BinOp (BAnd, p1, p2, ty) in
            let inv_xor  = apply_inv_perm perm xor_part ty in
            let inv_and  = apply_inv_perm perm and_part ty in
            let shift_and = BinOp (Shiftlt, inv_and, integer 1, ty) in
            let res = BinOp (PlusA, inv_xor, shift_and, ty) in
            ChangeTo res
          ) else DoChildren

      | _ -> DoChildren
  end

  let transform_file (f : file) : file =
    let vis = new bpm_visitor in
    visitCilFileSameGlobals (vis :> cilVisitor) f;
    f
end
