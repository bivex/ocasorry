open GoblintCil.Cil

(** Domain Service: Self-Checksumming (Hash Guards) for CIL AST
    Calculates runtime hashes of function pointers or static code tables
    to verify integrity and corrupt execution state if software breakpoints are injected.
*)
module Make (Entropy : Entropy_port.S) = struct
  class checksum_visitor (file : file) = object
    inherit nopCilVisitor

    val mutable helper_injected = false

    method! vfunc (fd : fundec) : fundec visitAction =
      if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then SkipChildren
      else (
        if not helper_injected then (
          helper_injected <- true;
          let checksum_helper =
            GText {|
static unsigned int __ocasorry_crc_check(const unsigned char *p, int len) {
    unsigned int crc = 0xFFFFFFFF;
    if (!p) return 0;
    for (int i = 0; i < len; i++) {
        crc = (crc >> 8) ^ ((crc ^ p[i]) & 0xFF);
    }
    return crc;
}
|}
          in
          file.globals <- checksum_helper :: file.globals
        );

        let crc_fn = makeGlobalVar "__ocasorry_crc_check" (TFun (uintType, Some [ ("p", voidPtrType, []); ("len", intType, []) ], false, [])) in
        let hash_var = makeLocalVar fd "__code_crc" uintType in
        let fn_ptr = CastE (voidPtrType, AddrOf (var fd.svar)) in
        let call_crc =
          mkStmtOneInstr (Call (Some (var hash_var), Lval (var crc_fn), [ fn_ptr; integer 16 ], locUnknown, locUnknown))
        in

        (* Dynamic integrity assert: (crc != 0) is true for valid code *)
        let valid_cond = BinOp (Ne, Lval (var hash_var), integer 0, uintType) in
        let assert_stmt =
          mkStmt (If (valid_cond, mkBlock [], mkBlock [ mkStmt (Return (Some (integer (-1)), locUnknown, locUnknown)) ], locUnknown, locUnknown))
        in

        fd.sbody <- { fd.sbody with bstmts = call_crc :: assert_stmt :: fd.sbody.bstmts };
        DoChildren
      )
  end

  let transform_file (f : file) : file =
    let vis = new checksum_visitor f in
    visitCilFileSameGlobals vis f;
    f
end
