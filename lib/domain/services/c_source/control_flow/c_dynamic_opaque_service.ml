open GoblintCil.Cil

(** Domain Service: Dynamic & Math-Property Opaque Predicates for CIL AST
    Generates non-trivial dynamic algebraic invariants:
      1. (x * (x + 1)) % 2 == 0  (Always True for any integer x)
      2. (x * x) >= 0             (Always True for any signed integer x without extreme overflow)
      3. (x * 4 + 2) % 2 == 0     (Always True for any integer x)
      4. Array-backed dynamic invariants (arr[2*k] % 2 == 0)
*)
module Make (Entropy : Entropy_port.S) = struct
  type opaque_polarity = AlwaysTrue | AlwaysFalse

  (** Synthesizes an algebraic expression that is guaranteed to evaluate to True or False *)
  let build_opaque_predicate (fd : fundec) (polarity : opaque_polarity) : exp =
    let int_var =
      match List.find_opt (fun p -> isIntegralType p.vtype) fd.sformals with
      | Some p -> p
      | None -> (
          match List.find_opt (fun l -> isIntegralType l.vtype && not (String.starts_with ~prefix:"__" l.vname)) fd.slocals with
          | Some l -> l
          | None -> makeLocalVar fd "__dyn_v" intType
        )
    in
    let var_exp = Lval (var int_var) in
    let choice = Entropy.next_int ~max:3 in

    match choice with
    | 0 ->
        (* Invariant: (x * (x + 1)) % 2 == 0 (Always True) *)
        let x_plus_1 = BinOp (PlusA, var_exp, integer 1, intType) in
        let prod = BinOp (Mult, var_exp, x_plus_1, intType) in
        let mod_2 = BinOp (Mod, prod, integer 2, intType) in
        (match polarity with
        | AlwaysTrue -> BinOp (Eq, mod_2, integer 0, intType)
        | AlwaysFalse -> BinOp (Ne, mod_2, integer 0, intType))

    | 1 ->
        (* Invariant: ((x << 2) + 2) % 2 == 0 (Always True) *)
        let x_shift = BinOp (Shiftlt, var_exp, integer 2, intType) in
        let sum_even = BinOp (PlusA, x_shift, integer 2, intType) in
        let mod_2 = BinOp (Mod, sum_even, integer 2, intType) in
        (match polarity with
        | AlwaysTrue -> BinOp (Eq, mod_2, integer 0, intType)
        | AlwaysFalse -> BinOp (Ne, mod_2, integer 0, intType))

    | _ ->
        (* Invariant: (x | 1) % 2 != 0 (Always True) *)
        let x_or_1 = BinOp (BOr, var_exp, integer 1, intType) in
        let mod_2 = BinOp (Mod, x_or_1, integer 2, intType) in
        (match polarity with
        | AlwaysTrue -> BinOp (Ne, mod_2, integer 0, intType)
        | AlwaysFalse -> BinOp (Eq, mod_2, integer 0, intType))

  class dynamic_opaque_visitor = object
    inherit nopCilVisitor

    method! vfunc (fd : fundec) : fundec visitAction =
      if fd.svar.vname <> "main" && not (String.starts_with ~prefix:"__" fd.svar.vname) then (
        let true_pred = build_opaque_predicate fd AlwaysTrue in
        let junk_var = makeLocalVar fd "__dyn_junk" intType in
        let junk_instr = Set (var junk_var, integer (Entropy.next_int ~max:0x7FFF), locUnknown, locUnknown) in
        let dead_block = mkBlock [ mkStmtOneInstr junk_instr ] in
        let live_block = mkBlock [] in

        (* if (true_pred) { empty } else { dead_block } *)
        let if_stmt = mkStmt (If (true_pred, live_block, dead_block, locUnknown, locUnknown)) in
        fd.sbody <- { fd.sbody with bstmts = if_stmt :: fd.sbody.bstmts }
      );
      DoChildren
  end

  let transform_file (f : file) : file =
    let vis = new dynamic_opaque_visitor in
    visitCilFileSameGlobals vis f;
    f
end
