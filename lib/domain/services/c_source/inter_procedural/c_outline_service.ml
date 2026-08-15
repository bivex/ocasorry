open GoblintCil.Cil

(** Domain Service: Function Outlining (Tigress Outline) for CIL AST
    Slices sequential statement blocks from function bodies into separate static
    subroutines (__outlined_chunk_N) passing local variables by pointer,
    breaking intra-procedural dataflow analysis in IDA / Ghidra.
*)
module Make (Entropy : Entropy_port.S) = struct
  class deref_visitor (ptr_map : (string, varinfo) Hashtbl.t) = object
    inherit nopCilVisitor

    method! vlval (lv : lval) : lval visitAction =
      match lv with
      | (Var v, NoOffset) when Hashtbl.mem ptr_map v.vname ->
          let ptr_formal = Hashtbl.find ptr_map v.vname in
          ChangeTo (Mem (Lval (var ptr_formal)), NoOffset)
      | _ -> DoChildren
  end

  let outline_counter = ref 0

  let is_outlinable (fd : fundec) : bool =
    fd.svar.vname <> "main"
    && not (String.starts_with ~prefix:"__" fd.svar.vname)
    && List.length fd.sbody.bstmts >= 2

  let outline_statements (file : file) (fd : fundec) : unit =
    let stmts = fd.sbody.bstmts in
    let len = List.length stmts in
    if len < 2 then ()
    else
      (* Extract the first half of statements into an outlined static function *)
      let slice_len = max 1 (len / 2) in
      let rec split n acc rest =
        if n = 0 || rest = [] then (List.rev acc, rest)
        else split (n - 1) (List.hd rest :: acc) (List.tl rest)
      in
      let (extracted_stmts, remaining_stmts) = split slice_len [] stmts in

      incr outline_counter;
      let outlined_name = Printf.sprintf "__outlined_%s_%d" fd.svar.vname !outline_counter in

      (* Collect local variables modified/used in extracted_stmts *)
      let used_vars =
        List.filter (fun v -> not v.vglob && not (String.starts_with ~prefix:"__" v.vname)) (fd.sformals @ fd.slocals)
      in

      if used_vars = [] then ()
      else
        (* Create parameter list for pointer arguments: int *v1, int *v2... *)
        let param_types =
          List.map (fun v -> (v.vname ^ "_ptr", TPtr (v.vtype, []), [])) used_vars
        in
        let fn_type = TFun (voidType, Some param_types, false, []) in
        let outlined_fd = emptyFunction outlined_name in
        setFunctionTypeMakeFormals outlined_fd fn_type;
        outlined_fd.svar.vstorage <- Static;

        (* Map original variables in extracted statements to dereferenced pointers *)
        let ptr_map = Hashtbl.create 8 in
        List.iter2
          (fun orig_v formal_ptr ->
            Hashtbl.add ptr_map orig_v.vname formal_ptr)
          used_vars outlined_fd.sformals;

        let vis = new deref_visitor ptr_map in
        let cloned_stmts =
          List.map
            (fun s ->
              let cl = { s with sid = s.sid } in
              visitCilStmt (vis :> cilVisitor) cl)
            extracted_stmts
        in
        outlined_fd.sbody <- mkBlock cloned_stmts;

        (* In caller (fd), replace extracted_stmts with a call to outlined_fd(&v1, &v2, ...) *)
        let call_args =
          List.map (fun v -> AddrOf (var v)) used_vars
        in
        let call_stmt =
          mkStmtOneInstr (Call (None, Lval (var outlined_fd.svar), call_args, locUnknown, locUnknown))
        in

        fd.sbody <- mkBlock (call_stmt :: remaining_stmts);
        file.globals <- (GFun (outlined_fd, locUnknown)) :: file.globals

  let transform_file (f : file) : file =
    let funcs =
      List.filter_map
        (function
          | GFun (fd, _) when is_outlinable fd -> Some fd
          | _ -> None)
        f.globals
    in
    List.iter (outline_statements f) funcs;
    f
end
