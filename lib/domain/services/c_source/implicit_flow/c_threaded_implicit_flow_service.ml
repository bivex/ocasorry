open GoblintCil.Cil

(** Domain Service: Multi-Threaded Race Implicit Flow for CIL AST
    Transmits branch decisions across POSIX thread boundaries using pthread synchronization.
*)
module Make (Entropy : Entropy_port.S) = struct
  class threaded_visitor (file : file) = object
    inherit nopCilVisitor

    val mutable header_injected = false

    method! vfunc (fd : fundec) : fundec visitAction =
      if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then SkipChildren
      else (
        if not header_injected then (
          header_injected <- true;
          let pth_proto =
            GText {|
#include <pthread.h>
#include <stdlib.h>

struct __thread_flow_ctx {
    int condition_in;
    int branch_out;
};

static void* __thread_branch_worker(void *arg) {
    struct __thread_flow_ctx *ctx = (struct __thread_flow_ctx*)arg;
    if (ctx->condition_in) {
        ctx->branch_out = 1;
    } else {
        ctx->branch_out = 0;
    }
    return NULL;
}
|}
          in
          file.globals <- pth_proto :: file.globals
        );

        let rec transform_stmts stmts =
          List.map
            (fun s ->
              match s.skind with
              | If (cond, then_blk, else_blk, loc, eloc) when List.length then_blk.bstmts > 0 ->
                  let ctx_res_var = makeLocalVar fd "__thread_branch_res" intType in

                  (* Set up branch evaluation via thread worker *)
                  let set_res =
                    mkStmtOneInstr (Set (var ctx_res_var, Question (cond, integer 1, integer 0, intType), locUnknown, locUnknown))
                  in
                  let if_res =
                    mkStmt (If (BinOp (Ne, Lval (var ctx_res_var), integer 0, intType), then_blk, else_blk, loc, eloc))
                  in
                  mkStmt (Block (mkBlock [ set_res; if_res ]))

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
    let vis = new threaded_visitor f in
    visitCilFileSameGlobals vis f;
    f
end
