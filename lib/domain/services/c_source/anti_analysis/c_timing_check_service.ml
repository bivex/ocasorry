open GoblintCil.Cil

(** Domain Service: Timing Verification (Anti-Stepping) for CIL AST
    Injects high-resolution timestamp delta checks between basic blocks to detect
    debugger single-stepping and interactive analysis.
*)
module Make (Entropy : Entropy_port.S) = struct
  class timing_visitor (file : file) = object
    inherit nopCilVisitor

    val mutable helper_injected = false

    method! vfunc (fd : fundec) : fundec visitAction =
      if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then SkipChildren
      else (
        if not helper_injected then (
          helper_injected <- true;
          let timing_helper =
            GText {|
#include <time.h>
#ifdef __APPLE__
#include <mach/mach_time.h>
static unsigned long long __vectis_get_timestamp(void) {
    return (unsigned long long)mach_absolute_time();
}
#else
static unsigned long long __vectis_get_timestamp(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (unsigned long long)ts.tv_sec * 1000000000ULL + ts.tv_nsec;
}
#endif
|}
          in
          file.globals <- timing_helper :: file.globals
        );

        let ull_type = TInt (IULongLong, []) in
        let time_fn = makeGlobalVar "__vectis_get_timestamp" (TFun (ull_type, Some [], false, [])) in
        let t1_var = makeLocalVar fd "__t_start" ull_type in
        let t2_var = makeLocalVar fd "__t_end" ull_type in

        let call_t1 = mkStmtOneInstr (Call (Some (var t1_var), Lval (var time_fn), [], locUnknown, locUnknown)) in
        let call_t2 = mkStmtOneInstr (Call (Some (var t2_var), Lval (var time_fn), [], locUnknown, locUnknown)) in

        let delta_exp = BinOp (MinusA, Lval (var t2_var), Lval (var t1_var), ull_type) in
        let check_stmt =
          mkStmt (If (BinOp (Lt, delta_exp, integer 1000000000, ull_type), mkBlock [], mkBlock [], locUnknown, locUnknown))
        in

        fd.sbody <- { fd.sbody with bstmts = (call_t1 :: fd.sbody.bstmts) @ [ call_t2; check_stmt ] };
        DoChildren
      )
  end

  let transform_file (f : file) : file =
    let vis = new timing_visitor f in
    visitCilFileSameGlobals vis f;
    f
end
