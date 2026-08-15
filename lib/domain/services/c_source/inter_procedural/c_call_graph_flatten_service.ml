open GoblintCil.Cil

(** Domain Service: Call Graph Flattening (Indirect Call Routing) for CIL AST
    Replaces direct call expressions with indirect function pointer lookups through
    a global dispatch table indexed by runtime hash identifiers.
*)
module Make (Entropy : Entropy_port.S) = struct
  class call_flatten_visitor (table_var : varinfo) (fn_map : (string, int) Hashtbl.t) = object
    inherit nopCilVisitor

    method! vstmt (s : stmt) : stmt visitAction =
      match s.skind with
      | Instr [ Call (ret_opt, Lval (Var fn_var, NoOffset), args, loc, eloc) ] ->
          if Hashtbl.mem fn_map fn_var.vname then (
            let idx = Hashtbl.find fn_map fn_var.vname in
            let table_elem = Lval (Var table_var, Index (integer idx, NoOffset)) in
            let fn_ptr_type = TPtr (fn_var.vtype, []) in
            let cast_fn_ptr = CastE (Explicit, fn_ptr_type, table_elem) in
            let indirect_lval = (Mem cast_fn_ptr, NoOffset) in
            let new_call = Call (ret_opt, Lval indirect_lval, args, loc, eloc) in
            ChangeTo (mkStmtOneInstr new_call)
          ) else DoChildren
      | _ -> DoChildren
  end

  let transform_file (f : file) : file =
    let funcs =
      List.filter_map
        (function
          | GFun (fd, _) when fd.svar.vname <> "main" && not (String.starts_with ~prefix:"__" fd.svar.vname) ->
              Some fd.svar
          | _ -> None)
        f.globals
    in
    if funcs = [] then f
    else (
      let table_size = List.length funcs in
      let fn_map = Hashtbl.create table_size in
      List.iteri (fun i v -> Hashtbl.add fn_map v.vname i) funcs;

      let void_ptr_ty = voidPtrType in
      let arr_ty = TArray (void_ptr_ty, Some (integer table_size), []) in
      let table_var = makeGlobalVar "__indirect_call_table" arr_ty in
      table_var.vstorage <- Static;

      let inits =
        List.mapi
          (fun i v ->
            let addr = AddrOf (Var v, NoOffset) in
            (Index (integer i, NoOffset), SingleInit (CastE (Explicit, void_ptr_ty, addr))))
          funcs
      in

      (* Forward declarations for all target functions so table can reference them *)
      let decls = List.map (fun v -> GVarDecl (v, locUnknown)) funcs in
      let table_global = GVar (table_var, { init = Some (CompoundInit (arr_ty, inits)) }, locUnknown) in

      f.globals <- decls @ (table_global :: f.globals);

      let vis = new call_flatten_visitor table_var fn_map in
      visitCilFileSameGlobals vis f;
      f
    )
end
