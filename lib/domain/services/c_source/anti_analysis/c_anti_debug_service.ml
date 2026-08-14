open GoblintCil.Cil

(** Domain Service: Anti-Debug Injection for CIL AST
    Injects inline kernel process inspection (sysctl P_TRACED / ptrace PT_DENY_ATTACH)
    to actively detect and terminate attached debuggers (LLDB, GDB).
*)
module Make (Entropy : Entropy_port.S) = struct
  class anti_debug_visitor (file : file) = object
    inherit nopCilVisitor

    val mutable helper_injected = false

    method! vfunc (fd : fundec) : fundec visitAction =
      if String.starts_with ~prefix:"__ocasorry_" fd.svar.vname then SkipChildren
      else (
        if not helper_injected then (
          helper_injected <- true;
          let debug_helper =
            GText {|
#include <sys/types.h>
#include <unistd.h>
#include <stdlib.h>

#ifdef __APPLE__
#include <sys/sysctl.h>
#include <dlfcn.h>
typedef int (*__ocasorry_ptrace_t)(int request, pid_t pid, void *addr, int data);

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
        if ((info.kp_proc.p_flag & 0x00000800) != 0) { /* P_TRACED */
            return 1;
        }
    }
    return 0;
}

static void __ocasorry_enforce_anti_debug(void) {
    if (__ocasorry_check_debugger_present()) {
        void *h = dlopen(0, 0);
        if (h) {
            __ocasorry_ptrace_t ptrace_fn = (__ocasorry_ptrace_t)dlsym(h, "ptrace");
            if (ptrace_fn) {
                ptrace_fn(31, 0, 0, 0); /* PT_DENY_ATTACH */
            }
        }
        exit(137); /* Fallback exit if ptrace returns */
    }
}
#else
static int __ocasorry_check_debugger_present(void) {
    return 0;
}
static void __ocasorry_enforce_anti_debug(void) {
    if (__ocasorry_check_debugger_present()) {
        exit(137);
    }
}
#endif
|}
          in
          file.globals <- debug_helper :: file.globals
        );

        let enforce_fn = makeGlobalVar "__ocasorry_enforce_anti_debug" (TFun (voidType, Some [], false, [])) in
        let call_enforce =
          mkStmtOneInstr (Call (None, Lval (var enforce_fn), [], locUnknown, locUnknown))
        in

        fd.sbody <- { fd.sbody with bstmts = call_enforce :: fd.sbody.bstmts };
        DoChildren
      )
  end

  let transform_file (f : file) : file =
    let vis = new anti_debug_visitor f in
    visitCilFileSameGlobals vis f;
    f
end
