open GoblintCil.Cil

(** Domain Service: Control Flow Flattening (CFF) for CIL AST *)
module Make (Entropy : Entropy_port.S) = struct
  let contains_return (s : stmt) : bool =
    match s.skind with
    | Return _ -> true
    | _ -> false

  class flattening_visitor = object
    inherit nopCilVisitor

    method! vfunc (fd : fundec) : fundec visitAction =
      let orig_stmts = fd.sbody.bstmts in
      if List.length orig_stmts >= 2 then (
        (* Create local state variable: int __cff_state; *)
        let state_var = makeLocalVar fd "__cff_state" intType in

        (* Generate randomized unique state numbers *)
        let n = List.length orig_stmts in
        let states = List.init n (fun i -> (i + 1) * 10 + Entropy.next_int ~max:9) in
        let entry_state = List.hd states in

        let case_stmts =
          List.mapi
            (fun i orig_stmt ->
              let curr_state = List.nth states i in
              let next_state =
                if i + 1 < n then List.nth states (i + 1) else 0
              in
              let case_label = Case (integer curr_state, locUnknown, locUnknown) in
              if contains_return orig_stmt then (
                orig_stmt.labels <- case_label :: orig_stmt.labels;
                orig_stmt
              ) else (
                let set_next_state =
                  mkStmtOneInstr (Set (var state_var, integer next_state, locUnknown, locUnknown))
                in
                let break_stmt = mkStmt (Break locUnknown) in
                let block_stmt =
                  mkStmt (Block (mkBlock [ orig_stmt; set_next_state; break_stmt ]))
                in
                block_stmt.labels <- case_label :: block_stmt.labels;
                block_stmt
              ))
            orig_stmts
        in

        (* Randomly shuffle case statements inside the switch *)
        let shuffled_cases = Entropy.shuffle case_stmts in
        let switch_block = mkBlock shuffled_cases in

        let switch_stmt =
          mkStmt (Switch (Lval (var state_var), switch_block, case_stmts, locUnknown, locUnknown))
        in

        (* Condition: while (__cff_state != 0) *)
        let cond_expr = BinOp (Ne, Lval (var state_var), integer 0, intType) in
        let if_check =
          mkStmt (If (cond_expr, mkBlock [ switch_stmt ], mkBlock [ mkStmt (Break locUnknown) ], locUnknown, locUnknown))
        in
        let loop_stmt = mkStmt (Loop (mkBlock [ if_check ], locUnknown, locUnknown, None, None)) in

        let init_state_stmt =
          mkStmtOneInstr (Set (var state_var, integer entry_state, locUnknown, locUnknown))
        in

        fd.sbody <- mkBlock [ init_state_stmt; loop_stmt ]
      );
      DoChildren
  end

  let transform_file (f : file) : file =
    let vis = new flattening_visitor in
    visitCilFileSameGlobals vis f;
    f
end
