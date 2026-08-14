open GoblintCil.Cil

(** Domain Service: Basic Block Splitting (O-LLVM SplitBasicBlocks)
    Splits contiguous basic blocks and statement sequences into fragmented blocks
    connected by explicit labels and unconditional goto jumps:
      stmt_1;
      goto __split_bb_1;
      __split_bb_1:
      stmt_2;
    disrupting token sequence locality, basic-block embeddings, and LLM attention windows.
*)
module Make (Entropy : Entropy_port.S) = struct
  let split_counter = ref 0

  let is_terminator (s : stmt) : bool =
    match s.skind with
    | Return _ | Break _ | Continue _ | Goto _ -> true
    | _ -> false

  let apply_split (fd : fundec) : unit =
    if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then ()
    else
      let orig_stmts = fd.sbody.bstmts in
      if List.length orig_stmts < 2 then ()
      else
        let new_stmts = ref [] in
        let rec process_stmts = function
          | [] -> ()
          | [ last ] -> new_stmts := last :: !new_stmts
          | s1 :: (s2 :: _ as tail) ->
              new_stmts := s1 :: !new_stmts;
              if not (is_terminator s1) then (
                incr split_counter;
                let lbl_name = Printf.sprintf "__split_bb_%d_%d" fd.svar.vid !split_counter in
                let target_stmt = s2 in
                target_stmt.labels <- Label (lbl_name, locUnknown, false) :: target_stmt.labels;
                let goto_stmt = mkStmt (Goto (ref target_stmt, locUnknown)) in
                new_stmts := goto_stmt :: !new_stmts
              );
              process_stmts tail
        in
        process_stmts orig_stmts;
        fd.sbody.bstmts <- List.rev !new_stmts

  let transform_file (f : file) : file =
    let funcs =
      List.filter_map
        (function
          | GFun (fd, _) -> Some fd
          | _ -> None)
        f.globals
    in
    List.iter apply_split funcs;
    f
end
