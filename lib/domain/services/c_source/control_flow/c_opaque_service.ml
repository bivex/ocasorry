open GoblintCil.Cil

(** Domain Service: Opaque Predicate Inserter for CIL AST
    Generates non-trivial opaque predicates resistant to:
    - SMT pattern databases (SYNTIA, D810)
    - LLM4Decompile / SALT4Decompile AST canonicalization
    Rotates through 4 distinct invariant classes per function:
      0. Quadratic parity:        (x*x + x) % 2 == 0    (x*(x+1) always even)
      1. Masked-OR identity:      (x | K) & K == K       (odd K always sets bit-0)
      2. Two's-complement zero:   (x + ~x + 1) == 0      (~x = -(x+1) → x + ~x + 1 = 0)
      3. Shift-mask identity:     (x >> k) << k == x & ~((1<<k)-1)
*)
module Make (Entropy : Entropy_port.S) = struct
  class opaque_visitor = object
    inherit nopCilVisitor

    method! vfunc (fd : fundec) : fundec visitAction =
      if fd.svar.vname <> "main" && not (String.starts_with ~prefix:"__" fd.svar.vname) then (
        let int_var =
          match List.find_opt (fun p -> isIntegralType p.vtype) fd.sformals with
          | Some p -> p
          | None -> (
              match List.find_opt (fun l -> isIntegralType l.vtype
                                         && not (String.starts_with ~prefix:"__" l.vname)) fd.slocals with
              | Some l -> l
              | None   -> makeLocalVar fd "__opaque_v" intType)
        in
        let var_exp = Lval (var int_var) in
        let var_ty  = int_var.vtype in
        let choice  = Entropy.next_int ~max:4 in

        let cond_exp : exp = match choice with
          | 0 ->
            (* (x*x + x) % 2 == 0  — D810 knows (x*(x+1))%2 but not the split form *)
            let xx   = BinOp (Mult,  var_exp, var_exp,   var_ty) in
            let xxpx = BinOp (PlusA, xx,      var_exp,   var_ty) in
            let m2   = BinOp (Mod,   xxpx,    integer 2, intType) in
            BinOp (Eq, m2, integer 0, intType)

          | 1 ->
            (* (x | K) & K == K  — random odd K; bypasses static-constant pattern matchers *)
            let k   = Entropy.next_int ~max:0x3FFE * 2 + 1 in
            let ko  = integer k in
            let ork = BinOp (BOr,  var_exp, ko, var_ty) in
            let ank = BinOp (BAnd, ork,     ko, intType) in
            BinOp (Eq, ank, ko, intType)

          | 2 ->
            (* (x + ~x + 1) == 0  — two's-complement identity; not in SYNTIA/D810 tables *)
            let nx    = UnOp  (BNot,  var_exp, var_ty) in
            let sum   = BinOp (PlusA, var_exp, nx,      var_ty) in
            let sump1 = BinOp (PlusA, sum,     integer 1, var_ty) in
            BinOp (Eq, sump1, integer 0, intType)

          | _ ->
            (* (x >> k) << k == x & ~((1<<k)-1)  — random shift k in [1..14] *)
            let k    = Entropy.next_int ~max:14 + 1 in
            let shr  = BinOp (Shiftrt, var_exp, integer k, var_ty) in
            let shl  = BinOp (Shiftlt, shr,     integer k, var_ty) in
            let mask = UnOp  (BNot, integer ((1 lsl k) - 1), var_ty) in
            let rhs  = BinOp (BAnd, var_exp, mask, var_ty) in
            BinOp (Eq, shl, rhs, intType)
        in

        let junk_instr =
          Set (var int_var, integer (Entropy.next_int ~max:0x7FFF), locUnknown, locUnknown)
        in
        let dead_block  = mkBlock [ mkStmtOneInstr junk_instr ] in
        let empty_block = mkBlock [] in
        let opaque_stmt = mkStmt (If (cond_exp, empty_block, dead_block, locUnknown, locUnknown)) in
        fd.sbody <- { fd.sbody with bstmts = opaque_stmt :: fd.sbody.bstmts }
      );
      DoChildren
  end

  let transform_file (f : file) : file =
    let vis = new opaque_visitor in
    visitCilFileSameGlobals vis f;
    f
end
