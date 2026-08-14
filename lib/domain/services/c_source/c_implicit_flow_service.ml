open GoblintCil.Cil

(** Domain Service: Implicit Flow (Signal / Exception Driven Control Flow) for CIL AST *)
module Make (Entropy : Entropy_port.S) = struct
  class implicit_flow_visitor (file : file) = object
    inherit nopCilVisitor

    val mutable handler_injected = false

    method! vfunc (fd : fundec) : fundec visitAction =
      (* Ensure signal headers / prototypes exist in file *)
      if not handler_injected then (
        handler_injected <- true;
        let sig_proto =
          GText {|
#include <signal.h>
#include <setjmp.h>

static sigjmp_buf __implicit_jmp_buf;
static void __implicit_signal_handler(int sig) {
    signal(11, __implicit_signal_handler);
    siglongjmp(__implicit_jmp_buf, 1);
}
|}
        in
        file.globals <- sig_proto :: file.globals
      );

      (* Replace top-level If statements with signal-driven dispatch *)
      let rec transform_stmts stmts =
        List.map
          (fun s ->
            match s.skind with
            | If (cond, then_blk, else_blk, loc, eloc) when List.length then_blk.bstmts > 0 ->
                let dummy_var = makeLocalVar fd "__implicit_dummy" intType in
                let ptr_var = makeLocalVar fd "__implicit_ptr" (TPtr (intType, [ Attr ("volatile", []) ])) in

                (* volatile int *__implicit_ptr = (cond) ? NULL : &__implicit_dummy; *)
                let null_ptr_exp = CastE (TPtr (intType, []), integer 0) in
                let dummy_addr_exp = AddrOf (var dummy_var) in
                let question_exp = Question (cond, null_ptr_exp, dummy_addr_exp, TPtr (intType, [])) in
                let set_ptr =
                  mkStmtOneInstr (Set (var ptr_var, question_exp, locUnknown, locUnknown))
                in

                (* *__implicit_ptr = 42; (Triggers SIGSEGV if cond was true) *)
                let ptr_deref = (Mem (Lval (var ptr_var)), NoOffset) in
                let set_deref =
                  mkStmtOneInstr (Set (ptr_deref, integer (1 + Entropy.next_int ~max:0xFF), locUnknown, locUnknown))
                in

                (* Call: signal(11, __implicit_signal_handler); (11 is SIGSEGV) *)
                let signal_fn = makeGlobalVar "signal" (TFun (voidPtrType, Some [ ("sig", intType, []); ("h", voidPtrType, []) ], false, [])) in
                let handler_var = makeGlobalVar "__implicit_signal_handler" (TFun (voidType, Some [ ("sig", intType, []) ], false, [])) in
                let call_signal =
                  mkStmtOneInstr
                    (Call (None, Lval (var signal_fn), [ integer 11; AddrOf (var handler_var) ], locUnknown, locUnknown))
                in

                (* Call: sigsetjmp(__implicit_jmp_buf, 1) == 0 *)
                let sigsetjmp_fn = makeGlobalVar "sigsetjmp" (TFun (intType, Some [ ("env", voidPtrType, []); ("save", intType, []) ], false, [])) in
                let jmp_buf_var = makeGlobalVar "__implicit_jmp_buf" voidPtrType in
                let setjmp_ret_var = makeLocalVar fd "__implicit_jmp_res" intType in
                let call_setjmp =
                  mkStmtOneInstr
                    (Call (Some (var setjmp_ret_var), Lval (var sigsetjmp_fn), [ AddrOf (var jmp_buf_var); integer 1 ], locUnknown, locUnknown))
                in

                let is_first_entry = BinOp (Eq, Lval (var setjmp_ret_var), integer 0, intType) in

                (* Branch 1: Normal execution -> if ptr==NULL it raises SIGSEGV; if ptr!=NULL it executes else_blk *)
                let normal_branch_block = mkBlock (set_ptr :: set_deref :: else_blk.bstmts) in
                (* Branch 2: Longjmp target -> signal caught, runs then_blk *)
                let signal_caught_block = then_blk in

                let implicit_if =
                  mkStmt (If (is_first_entry, normal_branch_block, signal_caught_block, loc, eloc))
                in

                mkStmt (Block (mkBlock [ call_signal; call_setjmp; implicit_if ]))

            | Block b ->
                { s with skind = Block { b with bstmts = transform_stmts b.bstmts } }
            | _ -> s)
          stmts
      in
      fd.sbody <- { fd.sbody with bstmts = transform_stmts fd.sbody.bstmts };
      DoChildren
  end

  let transform_file (f : file) : file =
    let vis = new implicit_flow_visitor f in
    visitCilFileSameGlobals vis f;
    f
end
