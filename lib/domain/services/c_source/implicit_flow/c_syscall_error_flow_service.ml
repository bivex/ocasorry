open GoblintCil.Cil

(** Domain Service: Syscall Error Return Flow for CIL AST
    Communicates boolean state via error return codes of intentionally failing system calls.
*)
module Make (Entropy : Entropy_port.S) = struct
  class syscall_visitor (file : file) = object
    inherit nopCilVisitor

    val mutable header_injected = false

    method! vfunc (fd : fundec) : fundec visitAction =
      if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then SkipChildren
      else (
        if not header_injected then (
          header_injected <- true;
          let unistd_proto =
            GText {|
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
|}
          in
          file.globals <- unistd_proto :: file.globals
        );

        let rec transform_stmts stmts =
          List.map
            (fun s ->
              match s.skind with
              | If (cond, then_blk, else_blk, loc, eloc) when List.length then_blk.bstmts > 0 ->
                  let sys_path_var = makeLocalVar fd "__sys_target_path" (TPtr (charType, [])) in
                  let sys_res_var = makeLocalVar fd "__sys_call_res" intType in

                  (* char *__sys_target_path = (cond) ? "/nonexistent_trap_path" : "/dev/null"; *)
                  let str_type = TPtr (charType, []) in
                  let trap_str = mkString "/__nonexistent_trap__" in
                  let devnull_str = mkString "/dev/null" in
                  let question_exp = Question (cond, trap_str, devnull_str, str_type) in
                  let set_path =
                    mkStmtOneInstr (Set (var sys_path_var, question_exp, locUnknown, locUnknown))
                  in

                  (* int __sys_call_res = access(__sys_target_path, 0); *)
                  let access_fn = makeGlobalVar "access" (TFun (intType, Some [ ("path", str_type, []); ("mode", intType, []) ], false, [])) in
                  let call_access =
                    mkStmtOneInstr
                      (Call (Some (var sys_res_var), Lval (var access_fn), [ Lval (var sys_path_var); integer 0 ], locUnknown, locUnknown))
                  in

                  (* If access failed (< 0, ENOENT), cond was true -> then_blk *)
                  let check_cond = BinOp (Lt, Lval (var sys_res_var), integer 0, intType) in
                  let sys_if =
                    mkStmt (If (check_cond, then_blk, else_blk, loc, eloc))
                  in

                  mkStmt (Block (mkBlock [ set_path; call_access; sys_if ]))

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
    let vis = new syscall_visitor f in
    visitCilFileSameGlobals vis f;
    f
end
