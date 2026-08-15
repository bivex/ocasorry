open GoblintCil.Cil

(** Domain Service: Irreducible Control-Flow Graph & Multi-Exit Loop Synthesizer (arXiv:2604.13675v1)
    Deconstructs natural single-entry loops into irreducible multi-entry graphs with
    interlocking cross-edges and non-post-dominating multi-exits, defeating decompiler
    loop structuring algorithms (Phoenix, NoMoreGotos, Ghidra).
*)
module Make (Entropy : Entropy_port.S) = struct
  let loop_counter = ref 0

  class loopTransformVisitor (fd : fundec) = object (_self)
    inherit nopCilVisitor

    method! vstmt s =
      match s.skind with
      | Loop (body, loc, _, _, _) ->
          incr loop_counter;
          let id = !loop_counter in
          let entry_a_label = Printf.sprintf "__irred_entry_A_%d" id in
          let entry_b_label = Printf.sprintf "__irred_entry_B_%d" id in
          let exit_1_label = Printf.sprintf "__irred_exit_1_%d" id in
          let exit_2_label = Printf.sprintf "__irred_exit_2_%d" id in
          let merge_label = Printf.sprintf "__irred_merge_%d" id in

          let irred_phase = makeLocalVar fd (Printf.sprintf "__irred_phase_%d" id) intType in
          let irred_exit_code = makeLocalVar fd (Printf.sprintf "__irred_exit_code_%d" id) intType in

          (* Create label statements *)
          let lbl_stmt_a = mkStmt (Instr []) in
          lbl_stmt_a.labels <- [ Label (entry_a_label, loc, false) ];

          let lbl_stmt_b = mkStmt (Instr []) in
          lbl_stmt_b.labels <- [ Label (entry_b_label, loc, false) ];

          let lbl_stmt_exit1 = mkStmt (Instr []) in
          lbl_stmt_exit1.labels <- [ Label (exit_1_label, loc, false) ];

          let lbl_stmt_exit2 = mkStmt (Instr []) in
          lbl_stmt_exit2.labels <- [ Label (exit_2_label, loc, false) ];

          let lbl_stmt_merge = mkStmt (Instr []) in
          lbl_stmt_merge.labels <- [ Label (merge_label, loc, false) ];

          (* Replace any Break statements in body with Goto Exit1 / Exit2 *)
          let replace_breaks (target_exit : stmt ref) (b : block) : block =
            let rec patch_stmts stmts =
              List.map
                (fun st ->
                  match st.skind with
                  | Break _ -> mkStmt (Goto (target_exit, loc))
                  | If (e, tb, fb, l1, l2) ->
                      mkStmt (If (e, { tb with bstmts = patch_stmts tb.bstmts },
                                     { fb with bstmts = patch_stmts fb.bstmts }, l1, l2))
                  | Block blk -> mkStmt (Block { blk with bstmts = patch_stmts blk.bstmts })
                  | _ -> st)
                stmts
            in
            { b with bstmts = patch_stmts b.bstmts }
          in

          let patched_body_a = replace_breaks (ref lbl_stmt_exit1) body in
          let patched_body_b = replace_breaks (ref lbl_stmt_exit2) body in

          (* Pre-dispatch selector: chooses entry A or entry B dynamically *)
          let init_phase =
            mkStmtOneInstr (Set (var irred_phase, integer (Entropy.next_int ~max:2), loc, loc))
          in

          let dispatch_entry =
            mkStmt (If (BinOp (Eq, Lval (var irred_phase), integer 0, intType),
                        mkBlock [ mkStmt (Goto (ref lbl_stmt_a, loc)) ],
                        mkBlock [ mkStmt (Goto (ref lbl_stmt_b, loc)) ],
                        loc, loc))
          in

          (* Cross-jumping back-edges: A -> B and B -> A *)
          let goto_b = mkStmt (Goto (ref lbl_stmt_b, loc)) in
          let goto_a = mkStmt (Goto (ref lbl_stmt_a, loc)) in

          (* Multi-exit paths with non-post-dominating intermediate handlers *)
          let exit1_handler =
            mkBlock [
              lbl_stmt_exit1;
              mkStmtOneInstr (Set (var irred_exit_code, integer 1, loc, loc));
              mkStmt (Goto (ref lbl_stmt_merge, loc));
            ]
          in
          let exit2_handler =
            mkBlock [
              lbl_stmt_exit2;
              mkStmtOneInstr (Set (var irred_exit_code, integer 2, loc, loc));
              mkStmt (Goto (ref lbl_stmt_merge, loc));
            ]
          in

          let transformed_block =
            mkBlock [
              init_phase;
              dispatch_entry;
              lbl_stmt_a;
              mkStmt (Block patched_body_a);
              goto_b;
              lbl_stmt_b;
              mkStmt (Block patched_body_b);
              goto_a;
              mkStmt (Block exit1_handler);
              mkStmt (Block exit2_handler);
              lbl_stmt_merge;
            ]
          in
          ChangeTo (mkStmt (Block transformed_block))
      | _ -> DoChildren
  end

  let should_transform (fd : fundec) : bool =
    if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then false
    else if not (C_annotation_service.AnnotationHelper.should_apply_pass fd "irreducible_loop") then false
    else true

  let transform_function (fd : fundec) : unit =
    if should_transform fd then (
      let visitor = new loopTransformVisitor fd in
      fd.sbody <- visitCilBlock visitor fd.sbody
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
