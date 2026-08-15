open GoblintCil.Cil

(** Domain Service: E-Graph Equality Expansion MBA Obfuscator
    Based on Scrambler (arXiv:2603.03624).
    Uses an E-graph (Equivalence Graph) data structure with Equality Expansion
    to synthesize deeply alternating, formally verified non-linear MBA expressions
    with semantics equivalence guaranteed by construction.
*)
module Make (Entropy : Entropy_port.S) = struct
  type eclass_id = int

  type enode =
    | EN_Const of int64 * typ
    | EN_Var of varinfo
    | EN_BinOp of binop * eclass_id * eclass_id * typ
    | EN_UnOp of unop * eclass_id * typ
    | EN_Cast of typ * eclass_id
    | EN_Leaf of exp

  type egraph = {
    mutable next_id : int;
    parent : (int, int) Hashtbl.t;
    classes : (int, enode list ref) Hashtbl.t;
    hashcons : (enode, int) Hashtbl.t;
  }

  let create_egraph () : egraph =
    {
      next_id = 0;
      parent = Hashtbl.create 64;
      classes = Hashtbl.create 64;
      hashcons = Hashtbl.create 64;
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

  let canon_node (eg : egraph) (node : enode) : enode =
    match node with
    | EN_BinOp (op, c1, c2, ty) -> EN_BinOp (op, find eg c1, find eg c2, ty)
    | EN_UnOp (op, c1, ty) -> EN_UnOp (op, find eg c1, ty)
    | EN_Cast (ty, c1) -> EN_Cast (ty, find eg c1)
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
      r1
    )

  let rec insert_exp (eg : egraph) (e : exp) : eclass_id =
    match e with
    | Const (CInt (i, _, _)) ->
        add_node eg (EN_Const (Z.to_int64 i, typeOf e))
    | Lval (Var v, NoOffset) ->
        add_node eg (EN_Var v)
    | BinOp (op, e1, e2, ty) ->
        let c1 = insert_exp eg e1 in
        let c2 = insert_exp eg e2 in
        add_node eg (EN_BinOp (op, c1, c2, ty))
    | UnOp (op, e1, ty) ->
        let c1 = insert_exp eg e1 in
        add_node eg (EN_UnOp (op, c1, ty))
    | CastE (Explicit, ty, e1) ->
        let c1 = insert_exp eg e1 in
        add_node eg (EN_Cast (ty, c1))
    | other ->
        add_node eg (EN_Leaf other)

  (** Apply 14 Sound Algebraic Rewrite Rules onto the E-Graph *)
  let apply_rules_on_node (eg : egraph) (cls : eclass_id) (node : enode) : unit =
    match node with
    (* --- PLUS RULES --- *)
    | EN_BinOp (PlusA, e1, e2, ty) when isIntegralType ty ->
        (* Rule 1: A + B = (A ^ B) + ((A & B) * 2) *)
        let xor_c = add_node eg (EN_BinOp (BXor, e1, e2, ty)) in
        let and_c = add_node eg (EN_BinOp (BAnd, e1, e2, ty)) in
        let two_c = add_node eg (EN_Const (2L, ty)) in
        let double_and = add_node eg (EN_BinOp (Mult, and_c, two_c, ty)) in
        let sum1_c = add_node eg (EN_BinOp (PlusA, xor_c, double_and, ty)) in
        ignore (union eg cls sum1_c);

        (* Rule 2: A + B = (A | B) + (A & B) *)
        let or_c = add_node eg (EN_BinOp (BOr, e1, e2, ty)) in
        let sum2_c = add_node eg (EN_BinOp (PlusA, or_c, and_c, ty)) in
        ignore (union eg cls sum2_c);

        (* Rule 3: A + B = A - ~B - 1 *)
        let one_c = add_node eg (EN_Const (1L, ty)) in
        let not_b = add_node eg (EN_UnOp (BNot, e2, ty)) in
        let sub1 = add_node eg (EN_BinOp (MinusA, e1, not_b, ty)) in
        let sub2 = add_node eg (EN_BinOp (MinusA, sub1, one_c, ty)) in
        ignore (union eg cls sub2);

        (* Rule 4: A + B = (A & B) + (A | B) [Commutative distribution] *)
        let sum3_c = add_node eg (EN_BinOp (PlusA, and_c, or_c, ty)) in
        ignore (union eg cls sum3_c)

    (* --- MINUS RULES --- *)
    | EN_BinOp (MinusA, e1, e2, ty) when isIntegralType ty ->
        (* Rule 5: A - B = (A ^ B) - ((~A & B) * 2) *)
        let xor_c = add_node eg (EN_BinOp (BXor, e1, e2, ty)) in
        let not_a = add_node eg (EN_UnOp (BNot, e1, ty)) in
        let and_na_b = add_node eg (EN_BinOp (BAnd, not_a, e2, ty)) in
        let two_c = add_node eg (EN_Const (2L, ty)) in
        let double_na_b = add_node eg (EN_BinOp (Mult, and_na_b, two_c, ty)) in
        let diff1_c = add_node eg (EN_BinOp (MinusA, xor_c, double_na_b, ty)) in
        ignore (union eg cls diff1_c);

        (* Rule 6: A - B = (A & ~B) - (~A & B) *)
        let not_b = add_node eg (EN_UnOp (BNot, e2, ty)) in
        let and_a_nb = add_node eg (EN_BinOp (BAnd, e1, not_b, ty)) in
        let diff2_c = add_node eg (EN_BinOp (MinusA, and_a_nb, and_na_b, ty)) in
        ignore (union eg cls diff2_c);

        (* Rule 7: A - B = (A + ~B) + 1 *)
        let one_c = add_node eg (EN_Const (1L, ty)) in
        let sum_a_nb = add_node eg (EN_BinOp (PlusA, e1, not_b, ty)) in
        let diff3_c = add_node eg (EN_BinOp (PlusA, sum_a_nb, one_c, ty)) in
        ignore (union eg cls diff3_c)

    (* --- XOR RULES --- *)
    | EN_BinOp (BXor, e1, e2, ty) when isIntegralType ty ->
        (* Rule 8: A ^ B = (A | B) - (A & B) *)
        let or_c = add_node eg (EN_BinOp (BOr, e1, e2, ty)) in
        let and_c = add_node eg (EN_BinOp (BAnd, e1, e2, ty)) in
        let xor1_c = add_node eg (EN_BinOp (MinusA, or_c, and_c, ty)) in
        ignore (union eg cls xor1_c);

        (* Rule 9: A ^ B = (A & ~B) | (~A & B) *)
        let not_a = add_node eg (EN_UnOp (BNot, e1, ty)) in
        let not_b = add_node eg (EN_UnOp (BNot, e2, ty)) in
        let and_a_nb = add_node eg (EN_BinOp (BAnd, e1, not_b, ty)) in
        let and_na_b = add_node eg (EN_BinOp (BAnd, not_a, e2, ty)) in
        let xor2_c = add_node eg (EN_BinOp (BOr, and_a_nb, and_na_b, ty)) in
        ignore (union eg cls xor2_c);

        (* Rule 10: A ^ B = (A & ~B) + (~A & B) *)
        let xor3_c = add_node eg (EN_BinOp (PlusA, and_a_nb, and_na_b, ty)) in
        ignore (union eg cls xor3_c)

    (* --- AND RULES --- *)
    | EN_BinOp (BAnd, e1, e2, ty) when isIntegralType ty ->
        (* Rule 11: A & B = (A | B) - (A ^ B) *)
        let or_c = add_node eg (EN_BinOp (BOr, e1, e2, ty)) in
        let xor_c = add_node eg (EN_BinOp (BXor, e1, e2, ty)) in
        let and1_c = add_node eg (EN_BinOp (MinusA, or_c, xor_c, ty)) in
        ignore (union eg cls and1_c);

        (* Rule 12: A & B = (A + B) - (A | B) *)
        let sum_c = add_node eg (EN_BinOp (PlusA, e1, e2, ty)) in
        let and2_c = add_node eg (EN_BinOp (MinusA, sum_c, or_c, ty)) in
        ignore (union eg cls and2_c)

    (* --- OR RULES --- *)
    | EN_BinOp (BOr, e1, e2, ty) when isIntegralType ty ->
        (* Rule 13: A | B = (A ^ B) + (A & B) *)
        let xor_c = add_node eg (EN_BinOp (BXor, e1, e2, ty)) in
        let and_c = add_node eg (EN_BinOp (BAnd, e1, e2, ty)) in
        let or1_c = add_node eg (EN_BinOp (PlusA, xor_c, and_c, ty)) in
        ignore (union eg cls or1_c);

        (* Rule 14: A | B = (A + B) - (A & B) *)
        let sum_c = add_node eg (EN_BinOp (PlusA, e1, e2, ty)) in
        let or2_c = add_node eg (EN_BinOp (MinusA, sum_c, and_c, ty)) in
        ignore (union eg cls or2_c)

    | _ -> ()

  (** Equality Expansion: Saturate / Expand E-Graph for N iterations *)
  let expand_egraph (eg : egraph) ~(iterations : int) ~(node_limit : int) : unit =
    for _iter = 1 to iterations do
      if Hashtbl.length eg.hashcons < node_limit then (
        let all_classes = Hashtbl.fold (fun id r acc -> (id, !r) :: acc) eg.classes [] in
        List.iter (fun (cls_id, nodes) ->
          List.iter (fun n ->
            if Hashtbl.length eg.hashcons < node_limit then
              apply_rules_on_node eg cls_id n
          ) nodes
        ) all_classes
      )
    done

  (** Compute Complexity / Obfuscation Metric of an E-Node *)
  let rec score_node (eg : egraph) (seen : (int, int) Hashtbl.t) (depth : int) (n : enode) : int =
    if depth > 8 then 0
    else match n with
    | EN_Const _ | EN_Var _ | EN_Leaf _ -> 1
    | EN_UnOp (_, c, _) | EN_Cast (_, c) ->
        1 + score_class eg seen (depth + 1) c
    | EN_BinOp (op, c1, c2, _) ->
        let op_weight = match op with
          | PlusA | MinusA -> 4
          | BXor -> 8
          | BAnd | BOr -> 6
          | Shiftlt | Shiftrt -> 5
          | _ -> 2
        in
        op_weight + score_class eg seen (depth + 1) c1 + score_class eg seen (depth + 1) c2

  and score_class (eg : egraph) (seen : (int, int) Hashtbl.t) (depth : int) (cls : eclass_id) : int =
    let r = find eg cls in
    match Hashtbl.find_opt seen r with
    | Some s -> s
    | None ->
        Hashtbl.replace seen r 0;
        let nodes = match Hashtbl.find_opt eg.classes r with
          | Some r_nodes -> !r_nodes
          | None -> []
        in
        let best = List.fold_left (fun acc n -> max acc (score_node eg seen depth n)) 0 nodes in
        Hashtbl.replace seen r best;
        best

  (** Extract Scrambled AST (Max-Complexity Walk) *)
  let rec extract_ast (eg : egraph) (visited : (int, exp) Hashtbl.t) (max_d : int) (cls : eclass_id) : exp =
    let r = find eg cls in
    match Hashtbl.find_opt visited r with
    | Some e -> e
    | None ->
        let nodes = match Hashtbl.find_opt eg.classes r with
          | Some r_nodes -> !r_nodes
          | None -> []
        in
        let pick_node =
          if max_d <= 0 || List.length nodes <= 1 then
            List.hd nodes
          else (
            (* Sort by score and pick with entropy from top variants *)
            let scored = List.map (fun n -> (score_node eg (Hashtbl.create 16) 0 n, n)) nodes in
            let sorted = List.sort (fun (s1, _) (s2, _) -> compare s2 s1) scored in
            let top_k = min 3 (List.length sorted) in
            let choice = Entropy.next_int ~max:top_k in
            snd (List.nth sorted choice)
          )
        in
        let res_exp = match pick_node with
          | EN_Const (i, _ty) -> Const (CInt (Z.of_int64 i, IInt, None))
          | EN_Var v -> Lval (Var v, NoOffset)
          | EN_Leaf e -> e
          | EN_UnOp (op, c, ty) ->
              let e_sub = extract_ast eg visited (max_d - 1) c in
              UnOp (op, e_sub, ty)
          | EN_Cast (ty, c) ->
              let e_sub = extract_ast eg visited (max_d - 1) c in
              CastE (Explicit, ty, e_sub)
          | EN_BinOp (op, c1, c2, ty) ->
              let e1 = extract_ast eg visited (max_d - 1) c1 in
              let e2 = extract_ast eg visited (max_d - 1) c2 in
              CastE (Explicit, ty, BinOp (op, e1, e2, ty))
        in
        Hashtbl.replace visited r res_exp;
        res_exp

  (** Top-Level Function: Obfuscate Expression via E-Graph Equality Expansion *)
  let obfuscate_exp (e : exp) ~(depth : int) : exp =
    if not (isIntegralType (typeOf e)) then e
    else (
      let eg = create_egraph () in
      let root_id = insert_exp eg e in
      expand_egraph eg ~iterations:depth ~node_limit:400;
      extract_ast eg (Hashtbl.create 32) (depth * 2) root_id
    )

  class egraph_mba_visitor ~(depth : int) ~(global_enabled : bool) = object
    inherit nopCilVisitor

    val mutable current_fn_enabled = false

    method! vfunc (fd : fundec) : fundec visitAction =
      if C_annotation_service.AnnotationHelper.should_skip_all fd then (
        current_fn_enabled <- false;
        SkipChildren
      ) else (
        current_fn_enabled <-
          (global_enabled && not (C_annotation_service.AnnotationHelper.has_any_vm_annotation fd)) ||
          C_annotation_service.AnnotationHelper.has_annotation fd "egraph_mba" ||
          C_annotation_service.AnnotationHelper.has_annotation fd "mba_egraph";
        DoChildren
      )

    method! vexpr (e : exp) : exp visitAction =
      if not current_fn_enabled then DoChildren
      else match e with
      | BinOp ((PlusA | MinusA | BXor | BAnd | BOr), _, _, ty) when isIntegralType ty ->
          let choice = Entropy.next_int ~max:10 in
          if choice < 7 then (* 70% probability of E-graph expansion on candidate operations *)
            ChangeTo (obfuscate_exp e ~depth)
          else DoChildren
      | _ -> DoChildren
  end

  let transform_file ?(depth : int = 3) ?(global : bool = true) (f : file) : file =
    let vis = new egraph_mba_visitor ~depth ~global_enabled:global in
    visitCilFileSameGlobals (vis :> cilVisitor) f;
    f
end
