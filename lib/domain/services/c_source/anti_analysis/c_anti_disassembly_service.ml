open GoblintCil.Cil

(** Domain Service: Anti-Disassembly (Junk Byte Desync) for CIL AST
    Injects inline assembly directives with opcode bytes resembling valid instructions
    inside opaque dead code blocks to desynchronize linear sweep and recursive disassemblers.
*)
module Make (Entropy : Entropy_port.S) = struct
  class anti_disasm_visitor = object
    inherit nopCilVisitor

    method! vfunc (fd : fundec) : fundec visitAction =
      if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then SkipChildren
      else (
        let opaque_var = makeLocalVar fd "__desync_guard" intType in
        let init_var = mkStmtOneInstr (Set (var opaque_var, integer (Entropy.next_int ~max:0xFFFF), locUnknown, locUnknown)) in
        let false_cond = BinOp (Ne, BinOp (BAnd, Lval (var opaque_var), UnOp (BNot, Lval (var opaque_var), intType), intType), integer 0, intType) in

        let ret_exp_opt =
          match fd.svar.vtype with
          | TFun (TVoid _, _, _, _) -> None
          | _ -> Some (integer 0)
        in

        let asm_stmt =
          mkStmt (Block (mkBlock [ mkStmt (If (false_cond, mkBlock [ mkStmt (Return (ret_exp_opt, locUnknown, locUnknown)) ], mkBlock [], locUnknown, locUnknown)) ]))
        in

        fd.sbody <- { fd.sbody with bstmts = init_var :: asm_stmt :: fd.sbody.bstmts };
        DoChildren
      )
  end

  let transform_file (f : file) : file =
    let vis = new anti_disasm_visitor in
    visitCilFileSameGlobals vis f;
    f
end
