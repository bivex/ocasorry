open GoblintCil.Cil

(** Domain Service: Function Inlining (Inline) for CIL AST
    Automatically inlines non-recursive helper functions across the AST.
*)
module Make (Entropy : Entropy_port.S) = struct
  class subst_visitor (formals : varinfo list) (args : exp list) = object
    inherit nopCilVisitor

    method! vexpr (e : exp) : exp visitAction =
      match e with
      | Lval (Var v, NoOffset) ->
          let rec find_idx i = function
            | [] -> None
            | hd :: _ when hd.vname = v.vname -> Some i
            | _ :: tl -> find_idx (i + 1) tl
          in
          (match find_idx 0 formals with
          | Some idx when idx < List.length args -> ChangeTo (List.nth args idx)
          | _ -> DoChildren)
      | _ -> DoChildren
  end

  let extract_return_expr (fd : fundec) : exp option =
    let rec find_ret = function
      | [] -> None
      | stmt :: rest ->
          (match stmt.skind with
          | Return (Some e, _, _) -> Some e
          | Block b -> (match find_ret b.bstmts with Some _ as res -> res | None -> find_ret rest)
          | _ -> find_ret rest)
    in
    find_ret fd.sbody.bstmts

  class inline_visitor (inlinable : (string, fundec) Hashtbl.t) = object
    inherit nopCilVisitor

    method! vstmt (s : stmt) : stmt visitAction =
      match s.skind with
      | Instr [ Call (Some ret_lval, Lval (Var fn_var, NoOffset), args, loc, eloc) ] ->
          if Hashtbl.mem inlinable fn_var.vname then (
            let target_fd = Hashtbl.find inlinable fn_var.vname in
            match extract_return_expr target_fd with
            | Some ret_exp ->
                let vis = new subst_visitor target_fd.sformals args in
                let inlined_exp = visitCilExpr vis ret_exp in
                let set_stmt = mkStmtOneInstr (Set (ret_lval, inlined_exp, loc, eloc)) in
                ChangeTo set_stmt
            | None -> DoChildren
          ) else DoChildren
      | _ -> DoChildren
  end

  let transform_file (f : file) : file =
    let inlinable = Hashtbl.create 16 in
    List.iter
      (function
        | GFun (fd, _) when fd.svar.vname <> "main" && not (String.starts_with ~prefix:"__" fd.svar.vname) ->
            if List.length fd.sbody.bstmts <= 3 then
              Hashtbl.add inlinable fd.svar.vname fd
        | _ -> ())
      f.globals;

    let vis = new inline_visitor inlinable in
    visitCilFileSameGlobals vis f;
    f
end
