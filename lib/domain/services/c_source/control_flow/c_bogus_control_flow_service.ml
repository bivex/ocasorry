open GoblintCil.Cil

(** Domain Service: Bogus Control Flow (BCF) for CIL AST
    Clones real basic blocks, mutates the clone with corrupted constants and dead computations,
    and places both behind a Dynamic Invariant Opaque Predicate:
      if (AlwaysTrueOpaque()) {
          Real_Basic_Block;
      } else {
          Mutated_Bogus_Block;
      }
*)
module Make (Entropy : Entropy_port.S) = struct
  module DynOpaque = C_dynamic_opaque_service.Make (Entropy)

  class mutate_visitor = object
    inherit nopCilVisitor

    method! vexpr (e : exp) : exp visitAction =
      match e with
      | Const (CInt (i, ik, s)) ->
          let mutated_val = Z.add i (Z.of_int (1 + Entropy.next_int ~max:0x7F)) in
          ChangeTo (Const (CInt (mutated_val, ik, s)))
      | _ -> DoChildren
  end

  let apply_bcf_to_function (fd : fundec) : unit =
    if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname
       || not (C_annotation_service.AnnotationHelper.should_apply_pass fd "bcf") then ()
    else
      let stmts = fd.sbody.bstmts in
      if List.length stmts < 2 then ()
      else
        let new_stmts = ref [] in
        List.iter
          (fun s ->
            match s.skind with
            | Instr instrs when instrs <> [] ->
                let cloned_s = { s with sid = s.sid; labels = [] } in
                let vis = new mutate_visitor in
                let bogus_s = visitCilStmt (vis :> cilVisitor) cloned_s in
                bogus_s.labels <- [];

                let pred = DynOpaque.build_opaque_predicate fd DynOpaque.AlwaysTrue in
                let real_block = mkBlock [ s ] in
                let bogus_block = mkBlock [ bogus_s ] in
                let bcf_if = mkStmt (If (pred, real_block, bogus_block, locUnknown, locUnknown)) in
                new_stmts := bcf_if :: !new_stmts

            | _ ->
                new_stmts := s :: !new_stmts)
          stmts;
        fd.sbody <- mkBlock (List.rev !new_stmts)

  let transform_file (f : file) : file =
    let funcs =
      List.filter_map
        (function
          | GFun (fd, _) -> Some fd
          | _ -> None)
        f.globals
    in
    List.iter apply_bcf_to_function funcs;
    f
end
