open GoblintCil.Cil

(** Domain Service: Instruction Substitution for CIL AST
    Replaces basic arithmetic/logical operations with equivalent algebraic substitution patterns:
    - x + 1 => -~x
    - x - 1 => ~-x
    - x + y => x - (-y)
    - x ^ y => (x | y) - (x & y)
*)
module Make (Entropy : Entropy_port.S) = struct
  class subst_visitor = object
    inherit nopCilVisitor

    method! vexpr (e : exp) : exp visitAction =
      match e with
      | BinOp (PlusA, e1, Const (CInt (v, _, _)), typ) when Z.equal v (Z.of_int 1) ->
          (* x + 1 => -~x *)
          let bnot_e = UnOp (BNot, e1, typ) in
          let neg_e = UnOp (Neg, bnot_e, typ) in
          ChangeTo neg_e
      | BinOp (MinusA, e1, Const (CInt (v, _, _)), typ) when Z.equal v (Z.of_int 1) ->
          (* x - 1 => ~-x *)
          let neg_e = UnOp (Neg, e1, typ) in
          let bnot_e = UnOp (BNot, neg_e, typ) in
          ChangeTo bnot_e
      | BinOp (BXor, e1, e2, typ) ->
          (* x ^ y => (x | y) - (x & y) *)
          let b_or = BinOp (BOr, e1, e2, typ) in
          let b_and = BinOp (BAnd, e1, e2, typ) in
          let res = BinOp (MinusA, b_or, b_and, typ) in
          ChangeTo res
      | BinOp (PlusA, e1, e2, typ) when not (isConstant e2) ->
          (* x + y => x - (-y) *)
          let neg_e2 = UnOp (Neg, e2, typ) in
          let res = BinOp (MinusA, e1, neg_e2, typ) in
          ChangeTo res
      | _ -> DoChildren
  end

  let transform_file (f : file) : file =
    let vis = new subst_visitor in
    visitCilFileSameGlobals vis f;
    f
end
