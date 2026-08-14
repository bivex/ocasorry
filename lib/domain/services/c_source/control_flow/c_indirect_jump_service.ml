open GoblintCil.Cil

(** Domain Service: Indirect Jump Tables (Computed Dispatch) for CIL AST
    Transforms structured linear blocks into an indirect table-driven dispatcher,
    routing state transitions through an array of indexed code labels.
*)
module Make (Entropy : Entropy_port.S) = struct
  let apply_indirect_jumps (fd : fundec) : unit =
    if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then ()
    else
      let stmts = fd.sbody.bstmts in
      if List.length stmts < 2 then ()
      else
        let state_var = makeLocalVar fd "__indirect_state" intType in
        let num_stmts = List.length stmts in
        let base_state = 100 + Entropy.next_int ~max:500 in

        let case_stmts = ref [] in
        List.iteri
          (fun idx s ->
            let state_id = base_state + (idx * 7) in
            let next_state_id =
              if idx + 1 < num_stmts then base_state + ((idx + 1) * 7) else 0
            in
            let update_state =
              mkStmtOneInstr (Set (var state_var, integer next_state_id, locUnknown, locUnknown))
            in
            let case_body = mkBlock [ s; update_state; mkStmt (Break locUnknown) ] in
            let case_stmt = mkStmt (Block case_body) in
            case_stmt.labels <- [ Case (integer state_id, locUnknown, locUnknown) ];
            case_stmts := case_stmt :: !case_stmts)
          stmts;

        let switch_stmt =
          mkStmt (Switch (Lval (var state_var), mkBlock (List.rev !case_stmts), [], locUnknown, locUnknown))
        in
        let loop_cond = BinOp (Ne, Lval (var state_var), integer 0, intType) in
        let loop_body = mkBlock [ switch_stmt ] in
        let dispatch_loop =
          mkStmt (If (loop_cond, mkBlock [ mkStmt (Loop (loop_body, locUnknown, locUnknown, None, None)) ], mkBlock [], locUnknown, locUnknown))
        in
        let init_state = mkStmtOneInstr (Set (var state_var, integer base_state, locUnknown, locUnknown)) in
        fd.sbody <- mkBlock [ init_state; dispatch_loop ]

  let transform_file (f : file) : file =
    let funcs =
      List.filter_map
        (function
          | GFun (fd, _) -> Some fd
          | _ -> None)
        f.globals
    in
    List.iter apply_indirect_jumps funcs;
    f
end
