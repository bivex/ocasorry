open GoblintCil.Cil

(** Domain Service: Function Merging (Tigress Merge) for CIL AST
    Merges pairs of independent C functions (e.g. calculate_area and calculate_perimeter)
    into a unified monolithic function:
      int __merged_fn(int __selector, int a0, int a1, int a2, int a3)
    controlled by randomized selector IDs.
*)
module Make (Entropy : Entropy_port.S) = struct
  class clone_visitor (formal_map : (string, varinfo) Hashtbl.t) (local_map : (string, varinfo) Hashtbl.t) = object
    inherit nopCilVisitor

    method! vvrbl (v : varinfo) : varinfo visitAction =
      if Hashtbl.mem formal_map v.vname then
        ChangeTo (Hashtbl.find formal_map v.vname)
      else if Hashtbl.mem local_map v.vname then
        ChangeTo (Hashtbl.find local_map v.vname)
      else
        DoChildren
  end

  let is_merge_candidate (fd : fundec) : bool =
    fd.svar.vname <> "main"
    && not (String.starts_with ~prefix:"__" fd.svar.vname)
    && List.length fd.sbody.bstmts > 0

  let merge_pair (file : file) (f1 : fundec) (f2 : fundec) : unit =
    let selector_1 = 0x1000 + Entropy.next_int ~max:0x7000 in
    let selector_2 = 0x8000 + Entropy.next_int ~max:0x7000 in
    let merged_name = Printf.sprintf "__merged_%s_%s" f1.svar.vname f2.svar.vname in

    (* Merged function signature: int __merged_X_Y(int __selector, int a0, int a1, int a2, int a3) *)
    let param_types = [
      ("__selector", intType, []);
      ("__arg0", intType, []);
      ("__arg1", intType, []);
      ("__arg2", intType, []);
      ("__arg3", intType, []);
    ] in
    let merged_fn_type = TFun (intType, Some param_types, false, []) in
    let merged_fd = emptyFunction merged_name in
    setFunctionTypeMakeFormals merged_fd merged_fn_type;
    merged_fd.svar.vstorage <- Static;

    let selector_formal = List.nth merged_fd.sformals 0 in
    let arg_formals = List.tl merged_fd.sformals in

    (* Helper to clone a function body into the merged function *)
    let clone_body_for (orig_fd : fundec) : block =
      let formal_map = Hashtbl.create 8 in
      List.iteri
        (fun idx f ->
          if idx < List.length arg_formals then
            Hashtbl.add formal_map f.vname (List.nth arg_formals idx))
        orig_fd.sformals;

      let local_map = Hashtbl.create 8 in
      List.iter
        (fun l ->
          let new_loc = makeLocalVar merged_fd (Printf.sprintf "__%s_%s" orig_fd.svar.vname l.vname) l.vtype in
          Hashtbl.add local_map l.vname new_loc)
        orig_fd.slocals;

      let vis = new clone_visitor formal_map local_map in
      let cloned_block = { orig_fd.sbody with bstmts = List.map (fun s -> { s with sid = s.sid }) orig_fd.sbody.bstmts } in
      visitCilBlock (vis :> cilVisitor) cloned_block
    in

    let body1 = clone_body_for f1 in
    let body2 = clone_body_for f2 in

    (* Construct selector switch:
       if (__selector == selector_1) { body1 }
       else if (__selector == selector_2) { body2 }
       else { return 0; }
    *)
    let cond1 = BinOp (Eq, Lval (var selector_formal), integer selector_1, intType) in
    let cond2 = BinOp (Eq, Lval (var selector_formal), integer selector_2, intType) in
    let else_fallback = mkBlock [ mkStmt (Return (Some (integer 0), locUnknown, locUnknown)) ] in
    let if2 = mkStmt (If (cond2, body2, else_fallback, locUnknown, locUnknown)) in
    let if1 = mkStmt (If (cond1, body1, mkBlock [ if2 ], locUnknown, locUnknown)) in
    merged_fd.sbody <- mkBlock [ if1 ];

    (* Replace original functions with proxy calls to merged_fd *)
    let rewrite_as_proxy (fd : fundec) (sel : int) =
      let call_args = ref [ integer sel ] in
      List.iteri
        (fun idx f ->
          if idx < 4 then
            call_args := !call_args @ [ Lval (var f) ])
        fd.sformals;
      while List.length !call_args < 5 do
        call_args := !call_args @ [ integer 0 ]
      done;

      let ret_var = makeLocalVar fd "__proxy_res" intType in
      let call_merged =
        mkStmtOneInstr (Call (Some (var ret_var), Lval (var merged_fd.svar), !call_args, locUnknown, locUnknown))
      in
      let ret_stmt = mkStmt (Return (Some (Lval (var ret_var)), locUnknown, locUnknown)) in
      fd.sbody <- mkBlock [ call_merged; ret_stmt ]
    in

    rewrite_as_proxy f1 selector_1;
    rewrite_as_proxy f2 selector_2;

    (* Prepend merged_fd before callers in globals list *)
    file.globals <- (GFun (merged_fd, locUnknown)) :: file.globals

  let transform_file (f : file) : file =
    let funcs =
      List.filter_map
        (function
          | GFun (fd, _) when is_merge_candidate fd -> Some fd
          | _ -> None)
        f.globals
    in

    let rec process_pairs = function
      | f1 :: f2 :: rest ->
          merge_pair f f1 f2;
          process_pairs rest
      | _ -> ()
    in
    process_pairs funcs;
    f
end
