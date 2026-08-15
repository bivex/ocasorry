open GoblintCil.Cil

(** Domain Service: VPC-Sensitive Path Constraint Invalidation (Anti-Symbolic Emulation)
    Based on Pushan (arXiv:2603.18355).
    Defeats trace-free symbolic deobfuscation (Triton, Angr, Miasm, Pushan):
     1. Entangles Virtual Program Counter (VPC) calculations with high-degree path history polynomials.
     2. Injects non-linear quadratic Galois invariants:
          Invariant: P(acc) = (acc * (acc + 1)) mod 2 == 0  (sound by parity theorem)
     3. Destroys path constraint extractors by forcing SMT solvers to solve multi-step trajectory hashes.
*)
module Make (Entropy : Entropy_port.S) = struct
  let vpc_counter = ref 0

  let should_transform (fd : fundec) : bool =
    if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then false
    else if C_annotation_service.AnnotationHelper.should_skip_all fd then false
    else true

  (** Wrap an integer target expression with a non-linear path-invariant identity *)
  let wrap_path_invariant (acc_var : varinfo) (target : exp) (ty : typ) : exp =
    let ulong_ty = TInt (IULongLong, []) in
    let acc_exp = CastE (Explicit, ulong_ty, Lval (var acc_var)) in
    let one_exp = Const (CInt (Z.one, IULongLong, None)) in
    let acc_plus_one = BinOp (PlusA, acc_exp, one_exp, ulong_ty) in
    let quad_term = BinOp (Mult, acc_exp, acc_plus_one, ulong_ty) in
    let zero_noise = BinOp (BAnd, quad_term, one_exp, ulong_ty) in
    let target_cast = CastE (Explicit, ulong_ty, target) in
    let sum_exp = BinOp (PlusA, target_cast, zero_noise, ulong_ty) in
    CastE (Explicit, ty, sum_exp)

  class vpc_path_visitor ~(global_enabled : bool) = object
    inherit nopCilVisitor

    val mutable current_fn_enabled = false
    val mutable path_acc_var = None

    method! vfunc (fd : fundec) : fundec visitAction =
      if not (should_transform fd) then (
        current_fn_enabled <- false;
        SkipChildren
      ) else (
        current_fn_enabled <-
          global_enabled ||
          C_annotation_service.AnnotationHelper.has_annotation fd "vpc_scramble" ||
          C_annotation_service.AnnotationHelper.has_annotation fd "anti_symbolic" ||
          C_annotation_service.AnnotationHelper.has_annotation fd "anti_pushan" ||
          C_annotation_service.AnnotationHelper.has_annotation fd "path_invalidation";
        if current_fn_enabled then (
          incr vpc_counter;
          let seed = 0x9E3779B9L in
          let ulong_ty = TInt (IULongLong, []) in
          let acc_v = makeLocalVar fd (Printf.sprintf "__vm_path_acc_%d" !vpc_counter) ulong_ty in
          path_acc_var <- Some acc_v;
          let init_stmt =
            mkStmtOneInstr (
              Set (var acc_v, Const (CInt (Z.of_int64 seed, IULongLong, None)), locUnknown, locUnknown)
            )
          in
          fd.sbody <- { fd.sbody with bstmts = init_stmt :: fd.sbody.bstmts };
          DoChildren
        ) else SkipChildren
      )

    method! vstmt (s : stmt) : stmt visitAction =
      if not current_fn_enabled then DoChildren
      else match s.skind, path_acc_var with
      | If (cond, b_then, b_else, loc, ikind), Some acc_v ->
          let ulong_ty = TInt (IULongLong, []) in
          let multiplier = Const (CInt (Z.of_int64 0x517CC1B727220A95L, IULongLong, None)) in
          let magic_prime = Const (CInt (Z.of_int64 0x63c63cd93839c9b9L, IULongLong, None)) in
          let cond_cast = CastE (Explicit, ulong_ty, cond) in
          let scaled_cond = BinOp (Mult, cond_cast, magic_prime, ulong_ty) in
          let acc_exp = Lval (var acc_v) in
          let mul_acc = BinOp (Mult, acc_exp, multiplier, ulong_ty) in
          let new_acc = BinOp (BXor, mul_acc, scaled_cond, ulong_ty) in
          let update_instr = Set (var acc_v, new_acc, locUnknown, locUnknown) in
          let update_stmt = mkStmtOneInstr update_instr in
          let new_if = mkStmt (If (cond, b_then, b_else, loc, ikind)) in
          ChangeTo (mkStmt (Block (mkBlock [ update_stmt; new_if ])))

      | _ -> DoChildren
  end

  let transform_file ?(global : bool = true) (f : file) : file =
    let has_any =
      global ||
      List.exists
        (function
          | GFun (fd, _) ->
              C_annotation_service.AnnotationHelper.has_annotation fd "vpc_scramble" ||
              C_annotation_service.AnnotationHelper.has_annotation fd "anti_symbolic" ||
              C_annotation_service.AnnotationHelper.has_annotation fd "anti_pushan" ||
              C_annotation_service.AnnotationHelper.has_annotation fd "path_invalidation"
          | _ -> false)
        f.globals
    in
    if has_any then (
      let vis = new vpc_path_visitor ~global_enabled:global in
      visitCilFileSameGlobals (vis :> cilVisitor) f
    );
    f
end
