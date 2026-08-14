open GoblintCil.Cil

(** Domain Service: Instruction Permutation (Def-Use Independence Scheduling)
    Reorders independent instructions and assignments within basic blocks
    while strictly preserving dataflow dependency invariants.
*)
module Make (Entropy : Entropy_port.S) = struct
  let are_independent_sets s1 s2 : bool =
    match (s1, s2) with
    | Set ((Var v1, NoOffset), e1, _, _), Set ((Var v2, NoOffset), e2, _, _) ->
        let e1_vars = ref [] in
        let e2_vars = ref [] in
        let vis1 = object
          inherit nopCilVisitor
          method! vlval = function (Var v, _) -> e1_vars := v.vname :: !e1_vars; DoChildren | _ -> DoChildren
        end in
        let vis2 = object
          inherit nopCilVisitor
          method! vlval = function (Var v, _) -> e2_vars := v.vname :: !e2_vars; DoChildren | _ -> DoChildren
        end in
        ignore (visitCilExpr vis1 e1);
        ignore (visitCilExpr vis2 e2);
        v1.vname <> v2.vname
        && not (List.mem v1.vname !e2_vars)
        && not (List.mem v2.vname !e1_vars)
    | _ -> false

  class permute_visitor = object
    inherit nopCilVisitor

    method! vblock (b : block) : block visitAction =
      let rec permute_instrs = function
        | i1 :: i2 :: rest when are_independent_sets i1 i2 && Entropy.next_int ~max:2 = 0 ->
            i2 :: i1 :: permute_instrs rest
        | i :: rest -> i :: permute_instrs rest
        | [] -> []
      in
      let new_stmts =
        List.map
          (fun s ->
            match s.skind with
            | Instr instrs -> { s with skind = Instr (permute_instrs instrs) }
            | _ -> s)
          b.bstmts
      in
      b.bstmts <- new_stmts;
      DoChildren
  end

  let transform_file (f : file) : file =
    let vis = new permute_visitor in
    visitCilFileSameGlobals vis f;
    f
end
