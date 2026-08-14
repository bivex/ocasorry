open GoblintCil.Cil

(** Domain Service: Dataflow-Entangled Anti-Slicing Computation
    Entangles phantom variables into the live computation paths using algebraic invariants:
      y = ((x ^ K) * 2) - (x ^ K) - (x ^ K) == 0
    Because y is mathematically identical to 0 but structurally dependent on x,
    adding y to live variables creates non-trivial Def-Use dependencies that static
    slicers and dead-code eliminators cannot remove without full symbolic evaluation.
*)
module Make (Entropy : Entropy_port.S) = struct
  class anti_slicing_visitor = object
    inherit nopCilVisitor

    val mutable current_func : fundec option = None

    method! vfunc (fd : fundec) : fundec visitAction =
      if fd.svar.vname <> "main" && not (String.starts_with ~prefix:"__" fd.svar.vname) then (
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
                            let ik = match typ with TInt (k, _) -> k | _ -> IInt in
                            let phantom_var = makeLocalVar fd (Printf.sprintf "__entangle_%d" (Entropy.next_int ~max:0xFFFF)) typ in
                            let k = kinteger64 ik (Int64.of_int (Entropy.next_int ~max:0x7FFF + 1)) in
                            let two = kinteger64 ik 2L in

                            (* 1. phantom = (dest ^ k) *)
                            let e_xor = BinOp (BXor, Lval dest, k, typ) in
                            let op1 = Set (var phantom_var, e_xor, loc, eloc) in

                            (* 2. phantom_scaled = phantom * 2 - phantom - phantom (== 0) *)
                            let e_mul = BinOp (Mult, Lval (var phantom_var), two, typ) in
                            let e_sub1 = BinOp (MinusA, e_mul, Lval (var phantom_var), typ) in
                            let e_sub2 = BinOp (MinusA, e_sub1, Lval (var phantom_var), typ) in
                            let op2 = Set (var phantom_var, e_sub2, loc, eloc) in

                            (* 3. dest = dest + phantom (Identity preserved: dest + 0 == dest) *)
                            let op3 = Set (dest, BinOp (PlusA, Lval dest, Lval (var phantom_var), typ), loc, eloc) in

                            new_instrs := op3 :: op2 :: op1 :: !new_instrs
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
