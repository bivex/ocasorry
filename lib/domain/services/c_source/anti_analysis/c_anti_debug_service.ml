open GoblintCil.Cil

(** Domain Service: Anti-Debug Injection for CIL AST
    Injects inline kernel process inspection (sysctl P_TRACED / ptrace) checks
    inside function basic blocks to detect and mitigate dynamic debuggers.
*)
module Make (Entropy : Entropy_port.S) = struct
  class anti_debug_visitor (file : file) = object
    inherit nopCilVisitor

    val mutable helper_injected = false

    method! vfunc (fd : fundec) : fundec visitAction =
      if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then SkipChildren
      else (
        if not helper_injected then (
          helper_injected <- true;
          let debug_helper =
            GText {|
#include <sys/types.h>
#include <unistd.h>

#ifdef __APPLE__
#include <sys/sysctl.h>
static int __ocasorry_check_debugger_present(void) {
    int mib[4];
    struct kinfo_proc info;
    size_t size = sizeof(info);
    info.kp_proc.p_flag = 0;
    mib[0] = 1; /* CTL_KERN */
    mib[1] = 14; /* KERN_PROC */
    mib[2] = 1; /* KERN_PROC_PID */
    mib[3] = getpid();
    if (sysctl(mib, 4, &info, &size, 0, 0) == 0) {
        return ((info.kp_proc.p_flag & 0x00000800) != 0); /* P_TRACED */
    }
    return 0;
}
#else
static int __ocasorry_check_debugger_present(void) {
    return 0;
}
#endif
|}
          in
          file.globals <- debug_helper :: file.globals
        );

        let check_fn = makeGlobalVar "__ocasorry_check_debugger_present" (TFun (intType, Some [], false, [])) in
        let dbg_flag = makeLocalVar fd "__is_dbg" intType in
        let call_check =
          mkStmtOneInstr (Call (Some (var dbg_flag), Lval (var check_fn), [], locUnknown, locUnknown))
        in

        (* If debugger is detected, corrupt local state or branch to trap *)
        let dbg_cond = BinOp (Ne, Lval (var dbg_flag), integer 0, intType) in
        let trap_stmt =
          mkStmt (If (dbg_cond, mkBlock [ mkStmt (Return (Some (integer 1337), locUnknown, locUnknown)) ], mkBlock [], locUnknown, locUnknown))
        in

        fd.sbody <- { fd.sbody with bstmts = call_check :: trap_stmt :: fd.sbody.bstmts };
        DoChildren
      )
  end

  let transform_file (f : file) : file =
    let vis = new anti_debug_visitor f in
    visitCilFileSameGlobals vis f;
    f
end
