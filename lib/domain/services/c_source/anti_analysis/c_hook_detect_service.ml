open GoblintCil.Cil

(** Domain Service: Dynamic Hook Detection for CIL AST
    Verifies function pointers and memory prologue bytes to detect Frida,
    Substrate, or Mach-O symbol interposing.
*)
module Make (Entropy : Entropy_port.S) = struct
  class hook_detect_visitor (file : file) = object
    inherit nopCilVisitor

    val mutable helper_injected = false

    method! vfunc (fd : fundec) : fundec visitAction =
      if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then SkipChildren
      else (
        if not helper_injected then (
          helper_injected <- true;
          let hook_helper =
            GText {|
static int __ocasorry_check_function_hook(const void *fn_ptr) {
    if (!fn_ptr) return 1;
    const unsigned char *code = (const unsigned char *)fn_ptr;
    /* Check for immediate hook trampoline opcodes: 0xE9 / 0xFF on x86, or invalid zero */
    if (code[0] == 0xE9 || (code[0] == 0xFF && code[1] == 0x25)) return 1; /* Hooked */
    return 0; /* Clean */
}
|}
          in
          file.globals <- hook_helper :: file.globals
        );

        let hook_fn = makeGlobalVar "__ocasorry_check_function_hook" (TFun (intType, Some [ ("fn_ptr", voidPtrType, []) ], false, [])) in
        let is_hooked_var = makeLocalVar fd "__is_hooked" intType in
        let fn_ptr = CastE (voidPtrType, AddrOf (var fd.svar)) in
        let call_hook_check =
          mkStmtOneInstr (Call (Some (var is_hooked_var), Lval (var hook_fn), [ fn_ptr ], locUnknown, locUnknown))
        in

        let hook_cond = BinOp (Ne, Lval (var is_hooked_var), integer 0, intType) in
        let abort_stmt =
          mkStmt (If (hook_cond, mkBlock [ mkStmt (Return (Some (integer (-99)), locUnknown, locUnknown)) ], mkBlock [], locUnknown, locUnknown))
        in

        fd.sbody <- { fd.sbody with bstmts = call_hook_check :: abort_stmt :: fd.sbody.bstmts };
        DoChildren
      )
  end

  let transform_file (f : file) : file =
    let vis = new hook_detect_visitor f in
    visitCilFileSameGlobals vis f;
    f
end
