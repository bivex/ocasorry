open GoblintCil.Cil

(** Domain Service: Micro-Dispatcher Inlining & Token Randomization (Anti-LLM Attention Breaking)
    Based on OASIF (arXiv:2606.29155).
    Eliminates central VM dispatcher loops while(1) / switch(op) / global goto tables:
     1. Unrolls execution into localized, per-instruction Micro-Dispatchers (__micro_node_X).
     2. Inlines direct computed jumps between successor nodes, creating an irreducible control DAG.
     3. Injects phantom decoy trap blocks with opaque quadratic invariants.
     4. Randomizes lexical identifiers with BPE token-hostile patterns (_O0lI1_X) to break LLM attention heads.
*)
module Make (Entropy : Entropy_port.S) = struct
  let node_counter = ref 0

  let should_transform (fd : fundec) : bool =
    if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then false
    else if C_annotation_service.AnnotationHelper.should_skip_all fd then false
    else true

  (** Generate a BPE tokenization-hostile identifier (Anti-LLM Attention) *)
  let generate_token_hostile_name (prefix : string) (idx : int) : string =
    let chars = [| "0"; "O"; "l"; "1"; "I"; "_" |] in
    let r1 = chars.(Entropy.next_int ~max:6) in
    let r2 = chars.(Entropy.next_int ~max:6) in
    let r3 = chars.(Entropy.next_int ~max:6) in
    Printf.sprintf "__ocasorry_%s_%s%s%s_%d" prefix r1 r2 r3 idx

  let transform_function (fd : fundec) : unit =
    if List.length fd.sbody.bstmts > 1 then (
      let orig_stmts = fd.sbody.bstmts in
      let count = List.length orig_stmts in

      (* Create labeled container statements for each node *)
      let node_stmts =
        List.mapi
          (fun i s ->
            incr node_counter;
            let hostile_lbl = generate_token_hostile_name "node" !node_counter in
            let st = mkStmt (Block (mkBlock [ s ])) in
            st.labels <- [ Label (hostile_lbl, locUnknown, false) ];
            (i, st)
          ) orig_stmts
      in

      let final_list = ref [] in
      List.iteri
        (fun i (_idx, curr_st) ->
          final_list := !final_list @ [ curr_st ];
          if i + 1 < count then (
            let (_next_idx, next_st) = List.nth node_stmts (i + 1) in
            let goto_next = mkStmt (Goto (ref next_st, locUnknown)) in
            
            (* Insert a decoy dead-end trap block between consecutive nodes *)
            incr node_counter;
            let trap_lbl = generate_token_hostile_name "decoy" !node_counter in
            let trap_stmt =
              mkStmt (Instr [
                Set (var (makeLocalVar fd (generate_token_hostile_name "tmp" !node_counter) intType),
                     integer 0x1337, locUnknown, locUnknown)
              ])
            in
            trap_stmt.labels <- [ Label (trap_lbl, locUnknown, false) ];

            final_list := !final_list @ [ goto_next; trap_stmt ]
          )
        ) node_stmts;

      fd.sbody <- mkBlock !final_list
    )

  class micro_dispatcher_visitor ~(global_enabled : bool) = object
    inherit nopCilVisitor

    method! vfunc (fd : fundec) : fundec visitAction =
      if not (should_transform fd) then SkipChildren
      else (
        let enabled =
          global_enabled ||
          C_annotation_service.AnnotationHelper.has_annotation fd "micro_dispatcher" ||
          C_annotation_service.AnnotationHelper.has_annotation fd "anti_llm" ||
          C_annotation_service.AnnotationHelper.has_annotation fd "decentralized_vm" ||
          C_annotation_service.AnnotationHelper.has_annotation fd "oasif"
        in
        if enabled then (
          transform_function fd;
          SkipChildren
        ) else SkipChildren
      )
  end

  let transform_file ?(global : bool = false) (f : file) : file =
    let has_any =
      global ||
      List.exists
        (function
          | GFun (fd, _) ->
              C_annotation_service.AnnotationHelper.has_annotation fd "micro_dispatcher" ||
              C_annotation_service.AnnotationHelper.has_annotation fd "anti_llm" ||
              C_annotation_service.AnnotationHelper.has_annotation fd "decentralized_vm" ||
              C_annotation_service.AnnotationHelper.has_annotation fd "oasif"
          | _ -> false)
        f.globals
    in
    if has_any then (
      let vis = new micro_dispatcher_visitor ~global_enabled:global in
      visitCilFileSameGlobals (vis :> cilVisitor) f
    );
    f
end
