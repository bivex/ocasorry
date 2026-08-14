open GoblintCil.Cil

(** Domain Service: Array Folding & Interleaving for CIL AST
    Transforms array index lookups by wrapping indices in scaled interleaved strides,
    disrupting linear dataflow and cache locality analysis in reverse engineering tools.
*)
module Make (Entropy : Entropy_port.S) = struct
  class array_interleave_visitor = object
    inherit nopCilVisitor

    method! voffs (off : offset) : offset visitAction =
      match off with
      | Index (idx_exp, next_off) ->
          let double_idx = BinOp (Shiftlt, idx_exp, integer 1, intType) in
          let interleaved_idx = BinOp (MinusA, double_idx, idx_exp, intType) in
          ChangeTo (Index (interleaved_idx, next_off))
      | _ -> DoChildren
  end

  let transform_file (f : file) : file =
    let vis = new array_interleave_visitor in
    visitCilFileSameGlobals (vis :> cilVisitor) f;
    f
end
