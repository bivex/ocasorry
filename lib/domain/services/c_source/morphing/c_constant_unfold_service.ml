open GoblintCil.Cil

(** Domain Service: Constant Unfolding for CIL AST
    Deconstructs static integer constants C into non-trivial polynomial/algebraic
    expansions: C => ((C ^ 0x5A5A) ^ 0x5A5A).
*)
module Make (Entropy : Entropy_port.S) = struct
  class constant_unfold_visitor = object
    inherit nopCilVisitor

    method! vexpr (e : exp) : exp visitAction =
      match e with
      | Const (CInt (v, ik, _)) when Z.gt v Z.zero && Z.lt v (Z.of_int 1000000) ->
          let typ = TInt (ik, []) in
          let mask = 0x5A5AL in
          let v_int64 = Z.to_int64 v in
          let enc_val = Int64.logxor v_int64 mask in
          let e_enc = kinteger64 ik enc_val in
          let e_mask = kinteger64 ik mask in
          let unfolded = BinOp (BXor, e_enc, e_mask, typ) in
          ChangeTo unfolded
      | _ -> DoChildren
  end

  let transform_file (f : file) : file =
    let vis = new constant_unfold_visitor in
    visitCilFileSameGlobals vis f;
    f
end
