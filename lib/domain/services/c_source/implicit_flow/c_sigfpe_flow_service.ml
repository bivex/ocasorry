open GoblintCil.Cil

(** Domain Service: Arithmetic Exception Flow (SIGFPE) for CIL AST
    Routes branch decisions through hardware/software arithmetic traps intercepted by signal handlers.
*)
module Make (Entropy : Entropy_port.S) = struct
  class sigfpe_visitor (file : file) = object
    inherit nopCilVisitor

    val mutable handler_injected = false

    method! vfunc (fd : fundec) : fundec visitAction =
      if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then SkipChildren
      else (
        if not handler_injected then (
          handler_injected <- true;
          let sig_proto =
            GText {|
#include <signal.h>
#include <setjmp.h>

static sigjmp_buf __sigfpe_jmp_buf;
static void __sigfpe_signal_handler(int sig) {
    signal(8, __sigfpe_signal_handler);
    siglongjmp(__sigfpe_jmp_buf, 1);
}
|}
          in
          file.globals <- sig_proto :: file.globals
        );

        let rec transform_stmts stmts =
          List.map
            (fun s ->
              match s.skind with
              | If (cond, then_blk, else_blk, loc, eloc) when List.length then_blk.bstmts > 0 ->
                  let denom_var = makeLocalVar fd "__fpe_denom" (TInt (IInt, [ Attr ("volatile", []) ])) in

                  (* volatile int __fpe_denom = (cond) ? 0 : 1; *)
                  let zero_exp = integer 0 in
                  let one_exp = integer 1 in
                  let question_exp = Question (cond, zero_exp, one_exp, intType) in
                  let set_denom =
                    mkStmtOneInstr (Set (var denom_var, question_exp, locUnknown, locUnknown))
                  in

                  (* If __fpe_denom == 0, trigger SIGFPE (8) *)
                  let raise_fn = makeGlobalVar "raise" (TFun (intType, Some [ ("sig", intType, []) ], false, [])) in
                  let trigger_fpe =
                    mkStmt (If (BinOp (Eq, Lval (var denom_var), integer 0, intType),
                                mkBlock [ mkStmtOneInstr (Call (None, Lval (var raise_fn), [ integer 8 ], locUnknown, locUnknown)) ],
                                mkBlock [], locUnknown, locUnknown))
                  in

                  (* Call: signal(8, __sigfpe_signal_handler); (8 is SIGFPE) *)
                  let signal_fn = makeGlobalVar "signal" (TFun (voidPtrType, Some [ ("sig", intType, []); ("h", voidPtrType, []) ], false, [])) in
                  let handler_var = makeGlobalVar "__sigfpe_signal_handler" (TFun (voidType, Some [ ("sig", intType, []) ], false, [])) in
                  let call_signal =
                    mkStmtOneInstr
                      (Call (None, Lval (var signal_fn), [ integer 8; AddrOf (var handler_var) ], locUnknown, locUnknown))
                  in

                  (* Call: sigsetjmp(__sigfpe_jmp_buf, 1) == 0 *)
                  let sigsetjmp_fn = makeGlobalVar "sigsetjmp" (TFun (intType, Some [ ("env", voidPtrType, []); ("save", intType, []) ], false, [])) in
                  let jmp_buf_var = makeGlobalVar "__sigfpe_jmp_buf" voidPtrType in
                  let setjmp_ret_var = makeLocalVar fd "__sigfpe_jmp_res" intType in
                  let call_setjmp =
                    mkStmtOneInstr
                      (Call (Some (var setjmp_ret_var), Lval (var sigsetjmp_fn), [ AddrOf (var jmp_buf_var); integer 1 ], locUnknown, locUnknown))
                  in

                  let is_first_entry = BinOp (Eq, Lval (var setjmp_ret_var), integer 0, intType) in

                  let normal_branch_block = mkBlock (set_denom :: trigger_fpe :: else_blk.bstmts) in
                  let signal_caught_block = then_blk in

                  let fpe_if =
                    mkStmt (If (is_first_entry, normal_branch_block, signal_caught_block, loc, eloc))
                  in

                  mkStmt (Block (mkBlock [ call_signal; call_setjmp; fpe_if ]))

              | Block b ->
                  { s with skind = Block { b with bstmts = transform_stmts b.bstmts } }
              | _ -> s)
            stmts
        in
        fd.sbody <- { fd.sbody with bstmts = transform_stmts fd.sbody.bstmts };
        DoChildren
      )
  end

  let transform_file (f : file) : file =
    let vis = new sigfpe_visitor f in
    visitCilFileSameGlobals vis f;
    f
end
