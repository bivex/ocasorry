open GoblintCil.Cil

(** Domain Service: Dynamic & Math-Property Opaque Predicates for CIL AST
    Generates non-trivial dynamic algebraic invariants resistant to:
    - Pattern databases (SYNTIA, D810, Decompile-Bench NeurIPS 2025)
    - LLM4Decompile / SALT4Decompile AST normalization
    6 predicate classes are rotated randomly per insertion:
      0. Consecutive product parity:  (x * (x+1)) % 2 == 0
      1. Shifted sum parity:          ((x << 2) + 2) % 2 == 0
      2. OR-odd identity:             (x | 1) % 2 != 0
      3. Two's-complement zero (new): (x + ~x + 1) == 0
      4. Quartic parity (new):        (x^4 + x^2) % 2 == 0   — (even^4 + even^2 = 0; odd^4 + odd^2 = 1+1 = 2 ≡ 0)
      5. Bitwise identity (new):      (x & K) | (x & ~K) == x  — partition identity
*)
module Make (Entropy : Entropy_port.S) = struct
  type opaque_polarity = AlwaysTrue | AlwaysFalse

  (** Synthesizes an algebraic expression that evaluates to True or False at runtime,
      but cannot be determined by compiler DCE, SYNTIA, or D810 pattern matchers. *)
  let build_opaque_predicate (fd : fundec) (polarity : opaque_polarity) : exp =
    let int_var =
      match List.find_opt (fun p -> isIntegralType p.vtype) fd.sformals with
      | Some p -> p
      | None -> (
          match List.find_opt (fun l -> isIntegralType l.vtype
                                     && not (String.starts_with ~prefix:"__" l.vname)) fd.slocals with
          | Some l -> l
          | None   -> makeLocalVar fd "__dyn_v" intType)
    in
    let var_exp = Lval (var int_var) in
    let var_ty  = int_var.vtype in
    let choice  = Entropy.next_int ~max:6 in

    match choice with
    | 0 ->
        (* (x * (x + 1)) % 2 == 0  — classic consecutive product parity *)
        let x1   = BinOp (PlusA, var_exp, integer 1, intType) in
        let prod = BinOp (Mult,  var_exp, x1,        intType) in
        let m2   = BinOp (Mod,   prod,    integer 2,  intType) in
        (match polarity with
        | AlwaysTrue  -> BinOp (Eq, m2, integer 0, intType)
        | AlwaysFalse -> BinOp (Ne, m2, integer 0, intType))

    | 1 ->
        (* ((x << 2) + 2) % 2 == 0  — shifting by 2 makes last bit 0, +2 stays even *)
        let x_shift = BinOp (Shiftlt, var_exp, integer 2, intType) in
        let sum_even = BinOp (PlusA,  x_shift, integer 2, intType) in
        let m2 = BinOp (Mod, sum_even, integer 2, intType) in
        (match polarity with
        | AlwaysTrue  -> BinOp (Eq, m2, integer 0, intType)
        | AlwaysFalse -> BinOp (Ne, m2, integer 0, intType))

    | 2 ->
        (* (x | 1) % 2 != 0  — OR with 1 always produces odd number *)
        let x_or_1 = BinOp (BOr, var_exp, integer 1, intType) in
        let m2 = BinOp (Mod, x_or_1, integer 2, intType) in
        (match polarity with
        | AlwaysTrue  -> BinOp (Ne, m2, integer 0, intType)
        | AlwaysFalse -> BinOp (Eq, m2, integer 0, intType))

    | 3 ->
        (* (x + ~x + 1) == 0  — two's-complement identity; NOT in D810/SYNTIA tables.
           Derivation: ~x = -(x+1), so x + ~x = -1, x + ~x + 1 = 0. *)
        let nx    = UnOp  (BNot,  var_exp, var_ty) in
        let sum   = BinOp (PlusA, var_exp, nx, var_ty) in
        let sump1 = BinOp (PlusA, sum, integer 1, var_ty) in
        (match polarity with
        | AlwaysTrue  -> BinOp (Eq, sump1, integer 0, intType)
        | AlwaysFalse -> BinOp (Ne, sump1, integer 0, intType))

    | 4 ->
        (* (x^2 * x^2 + x^2) % 2 == 0  — quartic identity (always even).
           x^2 is always 0 or 1 mod 2, so x^4 + x^2 ≡ 0 (mod 2). *)
        let x2  = BinOp (Mult, var_exp, var_exp, intType) in
        let x4  = BinOp (Mult, x2,      x2,       intType) in
        let sum = BinOp (PlusA, x4, x2, intType) in
        let m2  = BinOp (Mod,  sum, integer 2, intType) in
        (match polarity with
        | AlwaysTrue  -> BinOp (Eq, m2, integer 0, intType)
        | AlwaysFalse -> BinOp (Ne, m2, integer 0, intType))

    | _ ->
        (* (x & K) | (x & ~K) == x  — bitwise partition identity with random mask K.
           K partitions bits into two disjoint sets; their OR reconstructs x. *)
        let k    = Entropy.next_int ~max:0x3FFFFFFF + 1 in
        let ko   = integer k in
        let nk   = UnOp  (BNot,  ko, var_ty) in
        let hi   = BinOp (BAnd,  var_exp, ko,  var_ty) in
        let lo   = BinOp (BAnd,  var_exp, nk,  var_ty) in
        let reco = BinOp (BOr,   hi, lo, var_ty) in
        (match polarity with
        | AlwaysTrue  -> BinOp (Eq, reco, var_exp, intType)
        | AlwaysFalse -> BinOp (Ne, reco, var_exp, intType))

  class dynamic_opaque_visitor = object
    inherit nopCilVisitor

    method! vfunc (fd : fundec) : fundec visitAction =
      if fd.svar.vname <> "main" && not (String.starts_with ~prefix:"__" fd.svar.vname) then (
        let true_pred = build_opaque_predicate fd AlwaysTrue in
        let junk_var  = makeLocalVar fd "__dyn_junk" intType in
        let junk_instr = Set (var junk_var, integer (Entropy.next_int ~max:0x7FFF), locUnknown, locUnknown) in
        let dead_block = mkBlock [ mkStmtOneInstr junk_instr ] in
        let live_block = mkBlock [] in
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
