open GoblintCil.Cil

(** Domain Service: Relational Boundary & Comparison Morphing (PraPR Inspired / arXiv:1807.03512)
    Applies formal mutation and metamorphic equivalence transformations to relational
    and comparison expressions within CIL AST:
      1. Equality / Inequality Morphing:
         (a == b) <==> ((a ^ b) == 0)
         (a != b) <==> ((a ^ b) != 0)
      2. Strict Ordering Inversion:
         (a < b)  <==> ((a - b) < 0)  [signed] / !(a >= b)
         (a > b)  <==> ((b - a) < 0)  [signed] / !(a <= b)
      3. Boundary Shift Morphing:
         (a <= b) <==> ((a - b) <= 0) / !(a > b)
         (a >= b) <==> ((b - a) <= 0) / !(a < b)
      4. Null-Safe Dereference & Division Guards (DG/MG):
         (a / b)  <==> (b == 0 ? 0 : a / b)
*)
module Make (Entropy : Entropy_port.S) = struct

  class relational_morph_visitor = object
    inherit nopCilVisitor

    method! vexpr (e : exp) : exp visitAction =
      match e with
      | BinOp (Eq, e1, e2, ty) ->
          let choice = Entropy.next_int ~max:2 in
          if choice = 0 then
            let xor_exp = BinOp (BXor, e1, e2, ty) in
            let morphed = BinOp (Eq, xor_exp, integer 0, ty) in
            ChangeTo morphed
          else
            DoChildren

      | BinOp (Ne, e1, e2, ty) ->
          let choice = Entropy.next_int ~max:2 in
          if choice = 0 then
            let xor_exp = BinOp (BXor, e1, e2, ty) in
            let morphed = BinOp (Ne, xor_exp, integer 0, ty) in
            ChangeTo morphed
          else
            DoChildren

      | BinOp (Lt, e1, e2, ty) ->
          let choice = Entropy.next_int ~max:3 in
          if choice = 0 then
            let sub_exp = BinOp (MinusA, e1, e2, ty) in
            let morphed = BinOp (Lt, sub_exp, integer 0, ty) in
            ChangeTo morphed
          else if choice = 1 then
            let not_ge = UnOp (LNot, BinOp (Ge, e1, e2, ty), ty) in
            ChangeTo not_ge
          else
            DoChildren

      | BinOp (Gt, e1, e2, ty) ->
          let choice = Entropy.next_int ~max:3 in
          if choice = 0 then
            let sub_exp = BinOp (MinusA, e2, e1, ty) in
            let morphed = BinOp (Lt, sub_exp, integer 0, ty) in
            ChangeTo morphed
          else if choice = 1 then
            let not_le = UnOp (LNot, BinOp (Le, e1, e2, ty), ty) in
            ChangeTo not_le
          else
            DoChildren

      | BinOp (Le, e1, e2, ty) ->
          let choice = Entropy.next_int ~max:2 in
          if choice = 0 then
            let sub_exp = BinOp (MinusA, e1, e2, ty) in
            let morphed = BinOp (Le, sub_exp, integer 0, ty) in
            ChangeTo morphed
          else
            DoChildren

      | BinOp (Ge, e1, e2, ty) ->
          let choice = Entropy.next_int ~max:2 in
          if choice = 0 then
            let sub_exp = BinOp (MinusA, e2, e1, ty) in
            let morphed = BinOp (Le, sub_exp, integer 0, ty) in
            ChangeTo morphed
          else
            DoChildren

      | BinOp (Div, e1, e2, ty) ->
          let choice = Entropy.next_int ~max:3 in
          if choice = 0 then
            let is_zero = BinOp (Eq, e2, integer 0, intType) in
            let safe_div = Question (is_zero, integer 0, BinOp (Div, e1, e2, ty), ty) in
            ChangeTo safe_div
          else if choice = 1 then
            (* e2 == 0 ? 0 : (e1 / (e2 | (e2 == 0))) *)
            let is_zero = BinOp (Eq, e2, integer 0, ty) in
            let non_zero_denom = BinOp (BOr, e2, is_zero, ty) in
            let div_safe = BinOp (Div, e1, non_zero_denom, ty) in
            let safe_expr = Question (BinOp (Eq, e2, integer 0, intType), integer 0, div_safe, ty) in
            ChangeTo safe_expr
          else
            DoChildren

      | _ -> DoChildren
  end

  let transform_function (fd : fundec) : unit =
    if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then ()
    else (
      let vis = new relational_morph_visitor in
      fd.sbody <- visitCilBlock (vis :> cilVisitor) fd.sbody
    )

  let transform_file (f : file) : file =
    let funcs =
      List.filter_map
        (function
          | GFun (fd, _) -> Some fd
          | _ -> None)
        f.globals
    in
    List.iter transform_function funcs;
    f
end
