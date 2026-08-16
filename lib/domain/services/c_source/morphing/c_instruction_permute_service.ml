open GoblintCil.Cil

(** Domain Service: Instruction Permutation (Dataflow Dependency DAG Scheduling)
    Builds a fine-grained Read-After-Write (RAW), Write-After-Read (WAR), and
    Write-After-Write (WAW) dependency directed acyclic graph (DAG) for each
    instruction sequence, and generates a stochastically randomized topological
    linearization using Knuth/Fisher-Yates scheduling over the valid partial order.
    Defeats AST-level linear pattern matchers and SALT4Decompile / LLM4Decompile.
*)
module Make (Entropy : Entropy_port.S) = struct

  type instr_info = {
    instr : instr;
    writes : string list;
    reads : string list;
    is_barrier : bool;
  }

  let extract_lval_vars (lv : lval) : string list =
    let vars = ref [] in
    let vis = object
      inherit nopCilVisitor
      method! vlval = function
        | (Var v, _) ->
            vars := v.vname :: !vars;
            DoChildren
        | _ -> DoChildren
    end in
    ignore (visitCilLval vis lv);
    !vars

  let extract_expr_vars (e : exp) : string list =
    let vars = ref [] in
    let vis = object
      inherit nopCilVisitor
      method! vlval = function
        | (Var v, _) ->
            vars := v.vname :: !vars;
            DoChildren
        | _ -> DoChildren
    end in
    ignore (visitCilExpr vis e);
    !vars

  let analyze_instr (i : instr) : instr_info =
    match i with
    | Set (lv, e, _, _) ->
        let w = extract_lval_vars lv in
        let r = extract_expr_vars e in
        let is_ptr = match lv with (Mem _, _) -> true | _ -> false in
        { instr = i; writes = w; reads = r; is_barrier = is_ptr }
    | Call (opt_lv, callee, args, _, _) ->
        let w = match opt_lv with Some lv -> extract_lval_vars lv | None -> [] in
        let r_callee = extract_expr_vars callee in
        let r_args = List.concat_map extract_expr_vars args in
        { instr = i; writes = w; reads = r_callee @ r_args; is_barrier = true }
    | Asm _ ->
        { instr = i; writes = []; reads = []; is_barrier = true }
    | _ ->
        { instr = i; writes = []; reads = []; is_barrier = true }

  let has_conflict (prev : instr_info) (next : instr_info) : bool =
    if prev.is_barrier || next.is_barrier then true
    else
      let intersects l1 l2 = List.exists (fun x -> List.mem x l2) l1 in
      (* RAW: prev writes, next reads *)
      intersects prev.writes next.reads
      (* WAR: prev reads, next writes *)
      || intersects prev.reads next.writes
      (* WAW: both write *)
      || intersects prev.writes next.writes

  (** Topologically randomizes instructions according to the dependency DAG *)
  let permute_dag (instrs : instr list) : instr list =
    let n = List.length instrs in
    if n <= 1 then instrs
    else
      let infos = Array.of_list (List.map analyze_instr instrs) in
      let in_degree = Array.make n 0 in
      let adj = Array.make n [] in

      for i = 0 to n - 1 do
        for j = i + 1 to n - 1 do
          if has_conflict infos.(i) infos.(j) then (
            adj.(i) <- j :: adj.(i);
            in_degree.(j) <- in_degree.(j) + 1
          )
        done
      done;

      let ready = ref [] in
      for i = 0 to n - 1 do
        if in_degree.(i) = 0 then ready := i :: !ready
      done;

      let scheduled = ref [] in
      while !ready <> [] do
        let len = List.length !ready in
        let idx = Entropy.next_int ~max:len in
        let chosen = List.nth !ready idx in
        ready := List.filter (fun x -> x <> chosen) !ready;
        scheduled := infos.(chosen).instr :: !scheduled;

        List.iter
          (fun succ ->
            in_degree.(succ) <- in_degree.(succ) - 1;
            if in_degree.(succ) = 0 then ready := succ :: !ready)
          adj.(chosen)
      done;

      if List.length !scheduled = n then
        List.rev !scheduled
      else
        (* Fallback to original order if unexpected cycle (e.g. conservative barriers) *)
        instrs

  class permute_visitor = object
    inherit nopCilVisitor

    method! vblock (b : block) : block visitAction =
      let new_stmts =
        List.map
          (fun s ->
            match s.skind with
            | Instr instrs -> { s with skind = Instr (permute_dag instrs) }
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
