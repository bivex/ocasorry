open GoblintCil.Cil

(** Domain Service: Cross-Function Bogus Call Injection for CIL AST
    Injects dead function calls between unrelated functions guarded by opaque predicates
    to introduce false edges in decompiler and call-graph analysis tools.
*)
module Make (Entropy : Entropy_port.S) = struct
  class bogus_call_visitor (available_funcs : fundec list) = object
    inherit nopCilVisitor

    method! vfunc (fd : fundec) : fundec visitAction =
      if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then SkipChildren
      else (
        let other_funcs = List.filter (fun f -> f.svar.vname <> fd.svar.vname) available_funcs in
        if other_funcs <> [] then (
          let target_fn = List.hd other_funcs in
          let dummy_args =
            List.map
              (fun p ->
                if isIntegralType p.vtype then integer 0
                else CastE (Explicit, p.vtype, integer 0))
              target_fn.sformals
          in
          let bogus_call = Call (None, Lval (var target_fn.svar), dummy_args, locUnknown, locUnknown) in

          (* Guard behind opaque predicate: (x & ~x) != 0 (Always False) *)
          let x_var = makeLocalVar fd "__bogus_call_guard" intType in
          let init_x = mkStmtOneInstr (Set (var x_var, integer (Entropy.next_int ~max:0xFFFF), locUnknown, locUnknown)) in
          let not_x = UnOp (BNot, Lval (var x_var), intType) in
          let x_and_not_x = BinOp (BAnd, Lval (var x_var), not_x, intType) in
          let false_cond = BinOp (Ne, x_and_not_x, integer 0, intType) in

          let guarded_call =
            mkStmt (If (false_cond, mkBlock [ mkStmtOneInstr bogus_call ], mkBlock [], locUnknown, locUnknown))
          in
          fd.sbody <- { fd.sbody with bstmts = init_x :: guarded_call :: fd.sbody.bstmts }
        );
        DoChildren
      )
  end

  let transform_file (f : file) : file =
    let funcs =
      List.filter_map
        (function
          | GFun (fd, _) when fd.svar.vname <> "main" && not (String.starts_with ~prefix:"__" fd.svar.vname) ->
              Some fd
          | _ -> None)
        f.globals
    in
    if List.length funcs >= 2 then (
      let decls = List.map (fun fd -> GVarDecl (fd.svar, locUnknown)) funcs in
      f.globals <- decls @ f.globals;

      let vis = new bogus_call_visitor funcs in
      visitCilFileSameGlobals vis f;
      f
    ) else f
end
