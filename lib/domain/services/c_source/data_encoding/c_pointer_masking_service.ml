open GoblintCil.Cil

(** Domain Service: Pointer Swizzling & Masking for CIL AST
    Applies reversible XOR masking layers to pointer addresses at dereference sites,
    confusing dynamic taint tracking and automated pointer analysis engines.
*)
module Make (Entropy : Entropy_port.S) = struct
  let mask_val = 0x5A5AL

  class pointer_mask_visitor = object
    inherit nopCilVisitor

    method! vlval (lv : lval) : lval visitAction =
      match lv with
      | (Mem ptr_exp, offset) ->
          let ulong_ty = TInt (IULong, []) in
          let cast_to_ulong = CastE (ulong_ty, ptr_exp) in
          let mask_exp = Const (CInt (Z.of_int64 mask_val, IULong, None)) in
          let xor1 = BinOp (BXor, cast_to_ulong, mask_exp, ulong_ty) in
          let xor2 = BinOp (BXor, xor1, mask_exp, ulong_ty) in
          let unmasked_ptr = CastE (typeOf ptr_exp, xor2) in
          ChangeTo (Mem unmasked_ptr, offset)
      | _ -> DoChildren
  end

  let transform_file (f : file) : file =
    let vis = new pointer_mask_visitor in
    visitCilFileSameGlobals (vis :> cilVisitor) f;
    f
end
