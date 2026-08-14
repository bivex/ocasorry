open GoblintCil.Cil

(** Domain Service: Loop Unrolling & Jittering for CIL AST
    Locates Loop constructs, unrolls loop bodies by a factor of 2,
    and inserts non-interfering jitter computations to destroy loop symmetry.
*)
module Make (Entropy : Entropy_port.S) = struct
  class loop_unroll_visitor (fd : fundec) = object
    inherit nopCilVisitor

    method! vstmt (s : stmt) : stmt visitAction =
      match s.skind with
      | Loop (body, loc, loc2, break_opt, cont_opt) when List.length body.bstmts > 0 ->
          let jitter_var = makeLocalVar fd "__loop_jitter" intType in
          let jitter_instr1 =
            Set (var jitter_var, BinOp (BXor, Lval (var jitter_var), integer (Entropy.next_int ~max:0xFF), intType), locUnknown, locUnknown)
          in
          let jitter_instr2 =
            Set (var jitter_var, BinOp (PlusA, Lval (var jitter_var), integer (Entropy.next_int ~max:0x7F), intType), locUnknown, locUnknown)
          in

          let cloned_stmts =
            List.map (fun orig -> { orig with sid = orig.sid }) body.bstmts
          in
          let unrolled_stmts =
            (mkStmtOneInstr jitter_instr1) :: body.bstmts @
            (mkStmtOneInstr jitter_instr2) :: cloned_stmts
          in
          let new_body = { body with bstmts = unrolled_stmts } in
          ChangeTo (mkStmt (Loop (new_body, loc, loc2, break_opt, cont_opt)))

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
        let vis = new loop_unroll_visitor fd in
        fd.sbody <- visitCilBlock (vis :> cilVisitor) fd.sbody)
      funcs;
    f
end
