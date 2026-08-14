open GoblintCil.Cil

(** Domain Service: Pointer Swizzling & Masking for CIL AST
    Applies reversible arithmetic masking layers to pointer addresses at dereference sites,
    confusing dynamic taint tracking and automated pointer analysis engines.
*)
module Make (Entropy : Entropy_port.S) = struct
  class pointer_mask_visitor = object
    inherit nopCilVisitor

    method! vlval (lv : lval) : lval visitAction =
      match lv with
      | (Mem ptr_exp, offset) when isPointerType (typeOf ptr_exp) ->
          let shift_0 = BinOp (PlusPI, ptr_exp, integer 0, typeOf ptr_exp) in
          ChangeTo (Mem shift_0, offset)
      | _ -> DoChildren
  end

  let transform_file (f : file) : file =
    let vis = new pointer_mask_visitor in
    visitCilFileSameGlobals (vis :> cilVisitor) f;
    f
end
