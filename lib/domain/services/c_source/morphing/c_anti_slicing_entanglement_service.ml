open GoblintCil.Cil

(** Domain Service: Dataflow-Entangled Anti-Slicing Computation
    Entangles phantom variables into the live computation paths using algebraic invariants.
    Four distinct LLVM-resistant zero-identity patterns are selected at random per site:
      0. BNot/BOr/BAnd tautology            — blocks alias analysis
      1. Montgomery-style XOR self-cancel    — defeats constant propagation
      2. Double-key XOR undo                 — confuses value-range analysis
      3. OR/AND all-ones + AND-zero tautology — structurally opaque to InstCombine
    Each pattern evaluates to +0 at runtime but cannot be folded by LLVM at -O1/-O2.
*)
module Make (Entropy : Entropy_port.S) = struct
  class anti_slicing_visitor = object
    inherit nopCilVisitor

    val mutable current_func : fundec option = None
    val mutable entangle_id = 0

    method! vfunc (fd : fundec) : fundec visitAction =
      if fd.svar.vname <> "main" && not (String.starts_with ~prefix:"__" fd.svar.vname)
         && not (C_annotation_service.AnnotationHelper.should_skip_all fd) then (
        current_func <- Some fd;
        DoChildren
      ) else (
        current_func <- None;
        SkipChildren
      )

    method! vblock (b : block) : block visitAction =
      match current_func with
      | None -> DoChildren
      | Some fd ->
          let new_stmts = ref [] in
          List.iter
            (fun s ->
              match s.skind with
              | Instr instrs ->
                  let new_instrs = ref [] in
                  List.iter
                    (fun instr ->
                      new_instrs := instr :: !new_instrs;
                      match instr with
                      | Set (dest, _, loc, eloc) ->
                          let typ = typeOfLval dest in
                          if isIntegralType typ then (
                            entangle_id <- entangle_id + 1;
                            let ik = match typ with TInt (k, _) -> k | _ -> IInt in
                            let phantom_var = makeLocalVar fd (Printf.sprintf "__entangle_%s_%d" fd.svar.vname entangle_id) typ in

                            (* Pick one of 4 LLVM-resistant zero-identity patterns at random.
                               All patterns compute phantom == 0 so dest = dest + phantom == dest,
                               but each is structurally opaque to InstCombine / alias analysis. *)
                            let extra_instrs =
                              match Entropy.next_int ~max:4 with

                              | 0 ->
                                (* Pattern 0 — BNot/BOr/BAnd tautology (blocks alias analysis).
                                   phantom = dest ^ K
                                   phantom = phantom & ~(phantom | ~phantom)   == 0
                                   dest    = dest + phantom                    == dest *)
                                let k = kinteger64 ik (Int64.of_int (Entropy.next_int ~max:0x7FFF + 1)) in
                                let op1 = Set (var phantom_var, BinOp (BXor, Lval dest, k, typ), loc, eloc) in
                                let not_ph  = UnOp  (BNot, Lval (var phantom_var), typ) in
                                let or_ph   = BinOp (BOr,  Lval (var phantom_var), not_ph, typ) in
                                let and_not = BinOp (BAnd, Lval (var phantom_var), UnOp (BNot, or_ph, typ), typ) in
                                let op2 = Set (var phantom_var, and_not, loc, eloc) in
                                let op3 = Set (dest, BinOp (PlusA, Lval dest, Lval (var phantom_var), typ), loc, eloc) in
                                [ op1; op2; op3 ]

                              | 1 ->
                                (* Pattern 1 — Montgomery-style self-cancelling XOR.
                                   phantom = (dest * K1) ^ dest
                                   phantom = phantom ^ (dest * K1) ^ dest   == 0
                                   dest    = dest + phantom                  == dest *)
                                let k1 = kinteger64 ik (Int64.of_int (Entropy.next_int ~max:0x7FFF * 2 + 1)) in
                                let e_mul1 = BinOp (Mult, Lval dest, k1, typ) in
                                let op1 = Set (var phantom_var, BinOp (BXor, e_mul1, Lval dest, typ), loc, eloc) in
                                let e_mul2 = BinOp (Mult, Lval dest, k1, typ) in
                                let e_x2   = BinOp (BXor, Lval (var phantom_var), e_mul2, typ) in
                                let op2 = Set (var phantom_var, BinOp (BXor, e_x2, Lval dest, typ), loc, eloc) in
                                let op3 = Set (dest, BinOp (PlusA, Lval dest, Lval (var phantom_var), typ), loc, eloc) in
                                [ op1; op2; op3 ]

                              | 2 ->
                                (* Pattern 2 — Double-key XOR undo.
                                   phantom = (dest ^ K1) ^ K2
                                   phantom = phantom ^ K2 ^ K1 ^ dest   == 0
                                   dest    = dest + phantom              == dest *)
                                let k1 = kinteger64 ik (Int64.of_int (Entropy.next_int ~max:0x7FFF + 1)) in
                                let k2 = kinteger64 ik (Int64.of_int (Entropy.next_int ~max:0x7FFF + 1)) in
                                let op1 = Set (var phantom_var, BinOp (BXor, BinOp (BXor, Lval dest, k1, typ), k2, typ), loc, eloc) in
                                let e_undo = BinOp (BXor, BinOp (BXor, Lval (var phantom_var), k2, typ), k1, typ) in
                                let op2 = Set (var phantom_var, BinOp (BXor, e_undo, Lval dest, typ), loc, eloc) in
                                let op3 = Set (dest, BinOp (PlusA, Lval dest, Lval (var phantom_var), typ), loc, eloc) in
                                [ op1; op2; op3 ]

                              | _ ->
                                (* Pattern 3 — OR/AND all-ones tautology.
                                   phantom = (dest | ~dest) & 0   == 0
                                   dest    = dest + phantom       == dest *)
                                let not_dest = UnOp  (BNot, Lval dest, typ) in
                                let or_exp   = BinOp (BOr,  Lval dest, not_dest, typ) in
                                let and_zero = BinOp (BAnd, or_exp, integer 0, typ) in
                                let op1 = Set (var phantom_var, and_zero, loc, eloc) in
                                let op3 = Set (dest, BinOp (PlusA, Lval dest, Lval (var phantom_var), typ), loc, eloc) in
                                [ op1; op3 ]
                            in
                            new_instrs := List.rev_append extra_instrs !new_instrs
                          )
                      | _ -> ())
                    instrs;
                  new_stmts := { s with skind = Instr (List.rev !new_instrs) } :: !new_stmts
              | _ -> new_stmts := s :: !new_stmts)
            b.bstmts;
          b.bstmts <- List.rev !new_stmts;
          DoChildren
  end

  let transform_file (f : file) : file =
    let vis = new anti_slicing_visitor in
    visitCilFileSameGlobals vis f;
    f
end
