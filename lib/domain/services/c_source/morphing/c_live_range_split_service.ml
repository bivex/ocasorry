open GoblintCil.Cil

(** Domain Service: Live Range Splitting for CIL AST
    Splits the lifetime interval of local variables into distinct phased variables
    (e.g., v_phase2) connected by intermediate handover assignments.
*)
module Make (Entropy : Entropy_port.S) = struct
  class live_range_visitor (fd : fundec) = object
    inherit nopCilVisitor

    val mutable phase_var_map = Hashtbl.create 8

    method! vfunc (_ : fundec) : fundec visitAction =
      List.iter
        (fun v ->
          if isIntegralType v.vtype && not (String.starts_with ~prefix:"__" v.vname) then (
            let v_phase2 = makeVarinfo false (v.vname ^ "_phase2") v.vtype in
            fd.slocals <- v_phase2 :: fd.slocals;
            Hashtbl.add phase_var_map v.vname v_phase2
          ))
        fd.slocals;
      DoChildren

    method! vblock (b : block) : block visitAction =
      let new_stmts = ref [] in
      List.iter
        (fun s ->
          new_stmts := s :: !new_stmts;
          match s.skind with
          | Instr instrs ->
              List.iter
                (function
                  | Set ((Var v, NoOffset), _, loc, eloc) when Hashtbl.mem phase_var_map v.vname ->
                      let v2 = Hashtbl.find phase_var_map v.vname in
                      (* Handover assignment: v_phase2 = v ^ 0 *)
                      let handover = Set ((Var v2, NoOffset), BinOp (BXor, Lval (var v), integer 0, v.vtype), loc, eloc) in
                      new_stmts := mkStmtOneInstr handover :: !new_stmts
                  | _ -> ())
                instrs
          | _ -> ())
        b.bstmts;
      b.bstmts <- List.rev !new_stmts;
      DoChildren
  end

  let transform_file (f : file) : file =
    List.iter
      (function
        | GFun (fd, _) when fd.svar.vname <> "main" && not (String.starts_with ~prefix:"__" fd.svar.vname) ->
            let vis = new live_range_visitor fd in
            ignore (visitCilFunction vis fd)
        | _ -> ())
      f.globals;
    f
end
