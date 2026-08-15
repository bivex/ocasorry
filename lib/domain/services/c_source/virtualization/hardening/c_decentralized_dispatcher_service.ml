open GoblintCil.Cil

(** Domain Service: Decentralized Tree Dispatcher & Decoy Hub (Anti-VMTag / Anti-Topological Pass)
    Counters static virtualization-detection passes (such as LLVM VMTag / arXiv:2601.12916)
    that locate dispatchers by searching for max out-degree basic blocks (arg max D_out):
      1. Binary-Tree Dispatcher (Hierarchical Bounding):
         Deconstructs N-way switch dispatchers into balanced binary if-else decision trees
         where every basic block has out-degree D_out <= 2, completely erasing the hub signature.
      2. Decoy High-Degree Hub Bait:
         Injects an unreachable high-degree switch (32+ decoy cases) guarded by an unsolvable
         Diophantine opaque predicate (x^2 == 2 (mod 4)), causing static topological analyzers
         to misidentify the decoy hub as the "Dispatch Start" and extract bogus handlers.
*)
module Make (Entropy : Entropy_port.S) = struct
  let decoy_counter = ref 0

  let clean_case_stmt (s : stmt) : stmt =
    let clean_labels = List.filter (function Case _ | Default _ -> false | _ -> true) s.labels in
    let rec strip_breaks (st : stmt) : stmt =
      match st.skind with
      | Break _ -> mkStmt (Block (mkBlock []))
      | Block b ->
          let new_stmts = List.map strip_breaks b.bstmts in
          mkStmt (Block (mkBlock new_stmts))
      | _ -> st
    in
    let cleaned = strip_breaks s in
    cleaned.labels <- clean_labels;
    cleaned

  (** Recursively transforms a list of (case_val, stmt) into a balanced binary if-else tree *)
  let rec build_binary_dispatcher (selector : exp) (cases : (int * stmt) list) : stmt =
    match cases with
    | [] -> mkStmt (Block (mkBlock []))
    | [ (_, s) ] -> clean_case_stmt s
    | [ (v1, s1); (_, s2) ] ->
        let cond = BinOp (Eq, selector, integer v1, intType) in
        mkStmt (If (cond, mkBlock [ clean_case_stmt s1 ], mkBlock [ clean_case_stmt s2 ], locUnknown, locUnknown))
    | _ ->
        let len = List.length cases in
        let mid_idx = len / 2 in
        let left_cases = List.filteri (fun i _ -> i < mid_idx) cases in
        let right_cases = List.filteri (fun i _ -> i >= mid_idx) cases in
        let mid_val, _ = List.hd right_cases in
        let cond = BinOp (Lt, selector, integer mid_val, intType) in
        let left_stmt = build_binary_dispatcher selector left_cases in
        let right_stmt = build_binary_dispatcher selector right_cases in
        mkStmt (If (cond, mkBlock [ left_stmt ], mkBlock [ right_stmt ], locUnknown, locUnknown))

  (** Injects a decoy 32-way hub inside dead code guarded by Diophantine invariant *)
  let inject_decoy_hub (fd : fundec) : stmt =
    incr decoy_counter;
    let decoy_state = makeLocalVar fd (Printf.sprintf "__decoy_hub_state_%d" !decoy_counter) intType in
    let decoy_sink = makeLocalVar fd (Printf.sprintf "__decoy_hub_sink_%d" !decoy_counter) intType in

    (* Diophantine invariant: (x^2) % 4 == 2 is ALWAYS FALSE over integers *)
    let x_val = 100 + Entropy.next_int ~max:500 in
    let x_sq = x_val * x_val in
    let x_sq_mod_4 = x_sq mod 4 in (* Always 0 or 1, never 2 *)
    let opaque_cond = BinOp (Eq, integer x_sq_mod_4, integer 2, intType) in

    (* Build 32 fake handler cases to inflate D_out for topological scanners *)
    let fake_cases = ref [] in
    for i = 0 to 31 do
      let fake_body =
        mkBlock [
          mkStmtOneInstr (Set (var decoy_sink, BinOp (PlusA, Lval (var decoy_sink), integer (i * 7), intType), locUnknown, locUnknown));
          mkStmt (Break locUnknown);
        ]
      in
      let case_st = mkStmt (Block fake_body) in
      case_st.labels <- [ Case (integer (i * 3 + 1), locUnknown, locUnknown) ];
      fake_cases := case_st :: !fake_cases
    done;

    let decoy_switch =
      mkStmt (Switch (Lval (var decoy_state), mkBlock (List.rev !fake_cases), [], locUnknown, locUnknown))
    in
    mkStmt (If (opaque_cond, mkBlock [ decoy_switch ], mkBlock [], locUnknown, locUnknown))

  class decentralized_visitor (fd : fundec) = object
    inherit nopCilVisitor

    method! vstmt (s : stmt) : stmt visitAction =
      match s.skind with
      | Switch (selector, body, _, _, _) ->
          let case_pairs = ref [] in
          let rec extract_cases = function
            | [] -> ()
            | st :: rest ->
                let rec find_case_labels = function
                  | [] -> ()
                  | Case (e, _, _) :: _l_rest -> (
                      match e with
                      | Const (CInt (z, _, _)) ->
                          let v = Z.to_int z in
                          case_pairs := (v, st) :: !case_pairs
                      | _ -> ())
                  | _ :: l_rest -> find_case_labels l_rest
                in
                find_case_labels st.labels;
                (match st.skind with
                | Block b -> extract_cases b.bstmts
                | _ -> ());
                extract_cases rest
          in
          extract_cases body.bstmts;

          if List.length !case_pairs >= 2 then (
            let sorted_cases = List.sort (fun (v1, _) (v2, _) -> compare v1 v2) !case_pairs in
            let binary_tree_stmt = build_binary_dispatcher selector sorted_cases in
            let decoy_stmt = inject_decoy_hub fd in
            let combined = mkBlock [ decoy_stmt; binary_tree_stmt ] in
            ChangeTo (mkStmt (Block combined))
          ) else
            DoChildren
      | _ -> DoChildren
  end

  let transform_function (fd : fundec) : unit =
    if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then ()
    else (
      let vis = new decentralized_visitor fd in
      fd.sbody <- visitCilBlock (vis :> cilVisitor) fd.sbody
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
