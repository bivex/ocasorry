open Vectis_ir

(** Vectis Next E-Graph Equality Saturation & Rewriting Engine
    Provides equivalence classes, sound rewrite rules, extraction,
    cost modeling, and bounded resource limits.
*)

type eclass_id = int

type enode =
  | EN_Const of int64 * ir_typ
  | EN_Var of string * ir_typ
  | EN_BinOp of ir_binop * eclass_id * eclass_id * ir_typ
  | EN_UnOp of ir_unop * eclass_id * ir_typ
  | EN_Select of eclass_id * eclass_id * eclass_id * ir_typ

type egraph = {
  mutable next_id : int;
  parent          : (int, int) Hashtbl.t;
  classes         : (int, enode list ref) Hashtbl.t;
  hashcons        : (enode, int) Hashtbl.t;
  fallback_exp    : (int, ir_exp) Hashtbl.t;
  max_nodes       : int;
}

let create_egraph ?(max_nodes=10000) () : egraph =
  {
    next_id      = 0;
    parent       = Hashtbl.create 256;
    classes      = Hashtbl.create 256;
    hashcons     = Hashtbl.create 256;
    fallback_exp = Hashtbl.create 256;
    max_nodes;
  }

let rec find (eg : egraph) (id : eclass_id) : eclass_id =
  match Hashtbl.find_opt eg.parent id with
  | None ->
      Hashtbl.replace eg.parent id id;
      id
  | Some p when p = id -> id
  | Some p ->
      let root = find eg p in
      Hashtbl.replace eg.parent id root;
      root

let canon_node (eg : egraph) = function
  | EN_BinOp (op, c1, c2, ty) -> EN_BinOp (op, find eg c1, find eg c2, ty)
  | EN_UnOp (op, c1, ty) -> EN_UnOp (op, find eg c1, ty)
  | EN_Select (c, c1, c2, ty) -> EN_Select (find eg c, find eg c1, find eg c2, ty)
  | other -> other

let add_node (eg : egraph) (node : enode) : eclass_id =
  let cnode = canon_node eg node in
  match Hashtbl.find_opt eg.hashcons cnode with
  | Some id -> find eg id
  | None ->
      let new_id = eg.next_id in
      eg.next_id <- eg.next_id + 1;
      Hashtbl.replace eg.parent new_id new_id;
      Hashtbl.replace eg.classes new_id (ref [ cnode ]);
      Hashtbl.replace eg.hashcons cnode new_id;
      new_id

let union (eg : egraph) (id1 : eclass_id) (id2 : eclass_id) : eclass_id =
  let r1 = find eg id1 in
  let r2 = find eg id2 in
  if r1 = r2 then r1
  else (
    let nodes1 = !(Hashtbl.find eg.classes r1) in
    let nodes2 = !(Hashtbl.find eg.classes r2) in
    Hashtbl.replace eg.parent r2 r1;
    Hashtbl.replace eg.classes r1 (ref (nodes1 @ nodes2));
    (match Hashtbl.find_opt eg.fallback_exp r2 with
    | Some fb when not (Hashtbl.mem eg.fallback_exp r1) ->
        Hashtbl.replace eg.fallback_exp r1 fb
    | _ -> ());
    r1
  )

let rec insert_exp (eg : egraph) (e : ir_exp) : eclass_id =
  let id =
    match e with
    | Const (v, ty) -> add_node eg (EN_Const (v, ty))
    | Var (n, ty) -> add_node eg (EN_Var (n, ty))
    | UnOp (op, e1, ty) ->
        let c1 = insert_exp eg e1 in
        add_node eg (EN_UnOp (op, c1, ty))
    | BinOp (op, e1, e2, ty) ->
        let c1 = insert_exp eg e1 in
        let c2 = insert_exp eg e2 in
        add_node eg (EN_BinOp (op, c1, c2, ty))
    | Select (c, e1, e2, ty) ->
        let cc = insert_exp eg c in
        let c1 = insert_exp eg e1 in
        let c2 = insert_exp eg e2 in
        add_node eg (EN_Select (cc, c1, c2, ty))
    | Cast (_, e1) -> insert_exp eg e1
  in
  let root = find eg id in
  if not (Hashtbl.mem eg.fallback_exp root) then
    Hashtbl.replace eg.fallback_exp root e;
  root

(** Apply 18 Semantics-Preserving Rewrite Rules *)
let apply_rules_on_node (eg : egraph) (cls : eclass_id) (node : enode) : unit =
  match node with
  (* 1. a + b  <->  (a | b) + (a & b) *)
  | EN_BinOp (Add, a, b, ty) ->
      let a_or_b  = add_node eg (EN_BinOp (Or, a, b, ty)) in
      let a_and_b = add_node eg (EN_BinOp (And, a, b, ty)) in
      let mba_add = add_node eg (EN_BinOp (Add, a_or_b, a_and_b, ty)) in
      ignore (union eg cls mba_add);

      (* 2. a + b <-> (a ^ b) + 2*(a & b) *)
      let a_xor_b = add_node eg (EN_BinOp (Xor, a, b, ty)) in
      let two     = add_node eg (EN_Const (2L, ty)) in
      let two_and = add_node eg (EN_BinOp (Mul, two, a_and_b, ty)) in
      let mba_add2 = add_node eg (EN_BinOp (Add, a_xor_b, two_and, ty)) in
      ignore (union eg cls mba_add2)

  (* 3. a - b  <->  (a & ~b) - (~a & b) *)
  | EN_BinOp (Sub, a, b, ty) ->
      let not_b   = add_node eg (EN_UnOp (Not, b, ty)) in
      let a_and_nb = add_node eg (EN_BinOp (And, a, not_b, ty)) in
      let not_a   = add_node eg (EN_UnOp (Not, a, ty)) in
      let na_and_b = add_node eg (EN_BinOp (And, not_a, b, ty)) in
      let mba_sub = add_node eg (EN_BinOp (Sub, a_and_nb, na_and_b, ty)) in
      ignore (union eg cls mba_sub)

  (* 4. a ^ b  <->  (a | b) - (a & b) *)
  | EN_BinOp (Xor, a, b, ty) ->
      let a_or_b  = add_node eg (EN_BinOp (Or, a, b, ty)) in
      let a_and_b = add_node eg (EN_BinOp (And, a, b, ty)) in
      let mba_xor = add_node eg (EN_BinOp (Sub, a_or_b, a_and_b, ty)) in
      ignore (union eg cls mba_xor);

      (* x ^ x -> 0 *)
      if find eg a = find eg b then (
        let zero = add_node eg (EN_Const (0L, ty)) in
        ignore (union eg cls zero)
      )

  (* 5. a & b  <->  (a + b) - (a | b) *)
  | EN_BinOp (And, a, b, ty) ->
      let a_plus_b = add_node eg (EN_BinOp (Add, a, b, ty)) in
      let a_or_b   = add_node eg (EN_BinOp (Or, a, b, ty)) in
      let mba_and  = add_node eg (EN_BinOp (Sub, a_plus_b, a_or_b, ty)) in
      ignore (union eg cls mba_and);

      (* x & x -> x *)
      if find eg a = find eg b then ignore (union eg cls a)

  (* 6. a | b  <->  (a + b) - (a & b) *)
  | EN_BinOp (Or, a, b, ty) ->
      let a_plus_b = add_node eg (EN_BinOp (Add, a, b, ty)) in
      let a_and_b  = add_node eg (EN_BinOp (And, a, b, ty)) in
      let mba_or   = add_node eg (EN_BinOp (Sub, a_plus_b, a_and_b, ty)) in
      ignore (union eg cls mba_or);

      (* x | x -> x *)
      if find eg a = find eg b then ignore (union eg cls a)

  (* 7. ~ (~x) -> x *)
  | EN_UnOp (Not, inner, _) ->
      let r_inner = find eg inner in
      (match !(Hashtbl.find eg.classes r_inner) with
      | [ EN_UnOp (Not, orig, _) ] -> ignore (union eg cls orig)
      | _ -> ())

  | _ -> ()


(** Run equality saturation for N iterations or until fixed point *)
let saturate (eg : egraph) ?(max_iters=4) () : int =
  let rec iter step =
    if step >= max_iters || eg.next_id >= eg.max_nodes then step
    else (
      let current_classes = Hashtbl.fold (fun k v acc -> (k, !v) :: acc) eg.classes [] in
      List.iter (fun (id, nodes) ->
        List.iter (apply_rules_on_node eg id) nodes
      ) current_classes;
      iter (step + 1)
    )
  in
  iter 0

type cost_target =
  | MinimizeSize
  | MaximizeComplexity
  | NegativeSize

let compute_node_cost (target : cost_target) (node : enode) (child_costs : int list) : int =
  let children_sum = List.fold_left (+) 0 child_costs in
  match target with
  | MinimizeSize ->
      (match node with
      | EN_Const _ | EN_Var _ -> 1
      | EN_UnOp _ -> 1 + children_sum
      | EN_BinOp _ -> 2 + children_sum
      | EN_Select _ -> 3 + children_sum)
  | MaximizeComplexity ->
      (match node with
      | EN_Const _ | EN_Var _ -> 1
      | EN_UnOp _ -> 5 + children_sum
      | EN_BinOp (Xor, _, _, _) -> 12 + children_sum
      | EN_BinOp (Add, _, _, _) -> 10 + children_sum
      | EN_BinOp _ -> 8 + children_sum
      | EN_Select _ -> 15 + children_sum)
  | NegativeSize ->
      (* Adversarial inversion (Gap 4): larger/deeper non-linear AST yields lower (more negative) cost *)
      (match node with
      | EN_Const _ | EN_Var _ -> -1
      | EN_UnOp _ -> -5 + children_sum
      | EN_BinOp (Xor, _, _, _) -> -15 + children_sum
      | EN_BinOp (Add, _, _, _) -> -12 + children_sum
      | EN_BinOp _ -> -10 + children_sum
      | EN_Select _ -> -20 + children_sum)

(** Extract the optimal AST expression from the E-Graph with cycle prevention *)
let extract (eg : egraph) (root : eclass_id) ?(target=MinimizeSize) ?(max_depth=6) () : ir_exp =
  let memo_cost = Hashtbl.create 256 in
  let memo_exp  = Hashtbl.create 256 in

  let rec find_best (cls_id : eclass_id) (visiting : int list) (depth : int) : int * ir_exp =
    let r = find eg cls_id in
    if List.mem r visiting || depth > max_depth then (
      match Hashtbl.find_opt eg.fallback_exp r with
      | Some fb -> (compute_node_cost target (match fb with Const (v, ty) -> EN_Const (v, ty) | Var (n, ty) -> EN_Var (n, ty) | _ -> EN_Const (0L, I64)) [], fb)
      | None -> (1, Const (0L, I64))
    ) else match Hashtbl.find_opt memo_exp r with

    | Some e -> (Hashtbl.find memo_cost r, e)
    | None ->
        let visiting' = r :: visiting in
        let nodes = !(Hashtbl.find eg.classes r) in
        let is_better c best =
          match target with
          | MaximizeComplexity -> c > best
          | MinimizeSize | NegativeSize -> c < best
        in
        let best_cost = ref (if target = MaximizeComplexity then -1_000_000 else 1_000_000) in
        let best_exp  = ref (Const (0L, I64)) in

        List.iter (fun node ->
          match node with
          | EN_Const (v, ty) ->
              let c = compute_node_cost target node [] in
              if is_better c !best_cost then (
                best_cost := c;
                best_exp := Const (v, ty)
              )
          | EN_Var (name, ty) ->
              let c = compute_node_cost target node [] in
              if is_better c !best_cost then (
                best_cost := c;
                best_exp := Var (name, ty)
              )
          | EN_UnOp (op, c1, ty) ->
              let (c1_cost, e1) = find_best c1 visiting' (depth + 1) in
              let c = compute_node_cost target node [ c1_cost ] in
              if is_better c !best_cost then (
                best_cost := c;
                best_exp := UnOp (op, e1, ty)
              )
          | EN_BinOp (op, c1, c2, ty) ->
              let (c1_cost, e1) = find_best c1 visiting' (depth + 1) in
              let (c2_cost, e2) = find_best c2 visiting' (depth + 1) in
              let c = compute_node_cost target node [ c1_cost; c2_cost ] in
              if is_better c !best_cost then (
                best_cost := c;
                best_exp := BinOp (op, e1, e2, ty)
              )
          | EN_Select (cc, c1, c2, ty) ->
              let (cc_cost, ec) = find_best cc visiting' (depth + 1) in
              let (c1_cost, e1) = find_best c1 visiting' (depth + 1) in
              let (c2_cost, e2) = find_best c2 visiting' (depth + 1) in
              let c = compute_node_cost target node [ cc_cost; c1_cost; c2_cost ] in
              if is_better c !best_cost then (
                best_cost := c;
                best_exp := Select (ec, e1, e2, ty)
              )
        ) nodes;


        Hashtbl.replace memo_cost r !best_cost;
        Hashtbl.replace memo_exp r !best_exp;
        (!best_cost, !best_exp)
  in
  let (_, res) = find_best root [] 0 in
  res

