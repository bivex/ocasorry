open GoblintCil.Cil

(** Domain Service: Loop Fission & Fusion for CIL AST
    Splits multi-statement loop bodies into sequenced loop segments (Loop Fission)
    or merges serialized loop iteration blocks, preventing loop invariant analysis.
*)
module Make (Entropy : Entropy_port.S) = struct
  class loop_fission_visitor (fd : fundec) = object
    inherit nopCilVisitor

    method! vstmt (s : stmt) : stmt visitAction =
      match s.skind with
      | Loop (body, loc, loc2, break_opt, cont_opt) when List.length body.bstmts >= 4 ->
          let len = List.length body.bstmts in
          let mid = len / 2 in
          let rec split n acc rest =
            if n = 0 || rest = [] then (List.rev acc, rest)
            else split (n - 1) (List.hd rest :: acc) (List.tl rest)
          in
          let (part1, part2) = split mid [] body.bstmts in

          let phase_var = makeLocalVar fd "__loop_phase" intType in
          let set_phase1 = mkStmtOneInstr (Set (var phase_var, integer 1, locUnknown, locUnknown)) in
          let set_phase2 = mkStmtOneInstr (Set (var phase_var, integer 2, locUnknown, locUnknown)) in

          let if_phase1 =
            mkStmt (If (BinOp (Eq, Lval (var phase_var), integer 1, intType),
                        mkBlock (part1 @ [ set_phase2 ]),
                        mkBlock (part2 @ [ set_phase1 ]),
                        locUnknown, locUnknown))
          in
          let new_body = mkBlock [ if_phase1 ] in
          let init_phase = mkStmtOneInstr (Set (var phase_var, integer 1, locUnknown, locUnknown)) in
          let fission_block = mkBlock [ init_phase; mkStmt (Loop (new_body, loc, loc2, break_opt, cont_opt)) ] in
          ChangeTo (mkStmt (Block fission_block))

      | _ -> DoChildren
  end

  let transform_file (f : file) : file =
    let funcs =
      List.filter_map
        (function
          | GFun (fd, _) when fd.svar.vname <> "main" && not (String.starts_with ~prefix:"__" fd.svar.vname) -> Some fd
          | _ -> None)
        f.globals
    in
    List.iter
      (fun fd ->
        let vis = new loop_fission_visitor fd in
        fd.sbody <- visitCilBlock (vis :> cilVisitor) fd.sbody)
      funcs;
    f
end
