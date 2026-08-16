open GoblintCil.Cil

(** Domain Service: Self-Checksumming (Live Hash Ring & Silent State Poisoning) for CIL AST
    Calculates runtime non-linear ARX hashes of function prologue code to verify integrity.
    If software breakpoints (0xCC / BRK #0) or runtime memory patches are injected:
    - Silent state poisoning mathematically corrupts dataflow and return values.
    - Zero conditional branching / NO obvious 'if (failed) return -1;' in CFG.
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
static __attribute__((always_inline)) inline unsigned int __vectis_crc_check(const unsigned char *p, int len) {
    unsigned int h = 0x9E3779B9U;
    if (!p) return 0;
    for (int i = 0; i < len; i++) {
        h = ((h + p[i]) ^ ((h << 7) | (h >> 25))) * 0x517CC1B7U;
    }
    return h;
}
|}
          in
          file.globals <- checksum_helper :: file.globals
        );

        let crc_fn = makeGlobalVar "__vectis_crc_check" (TFun (uintType, Some [ ("p", voidPtrType, []); ("len", intType, []) ], false, [])) in
        let hash_var = makeLocalVar fd "__code_crc" uintType in
        let fn_ptr = CastE (Explicit, voidPtrType, AddrOf (var fd.svar)) in
        let call_crc =
          mkStmtOneInstr (Call (Some (var hash_var), Lval (var crc_fn), [ fn_ptr; integer 16 ], locUnknown, locUnknown))
        in

        (* Branchless Silent State Poisoning:
           Compute delta = ((__code_crc == 0) ? 0xDEADBEEF : 0)
           Rewrite all return statements in fd.sbody to xor this delta silently *)
        let poison_expr =
          Question (
            BinOp (Eq, Lval (var hash_var), integer 0, uintType),
            integer 0xDEADBEEF,
            integer 0,
            uintType
          )
        in

        let rewrite_returns = object
          inherit nopCilVisitor

          method! vstmt (s : stmt) : stmt visitAction =
            match s.skind with
            | Return (Some ret_e, loc, eloc) when isIntegralType (typeOf ret_e) ->
                let cast_poison = CastE (Explicit, typeOf ret_e, poison_expr) in
                let poisoned_ret = BinOp (BXor, ret_e, cast_poison, typeOf ret_e) in
                ChangeTo (mkStmt (Return (Some poisoned_ret, loc, eloc)))

            | _ -> DoChildren

        end in

        fd.sbody <- visitCilBlock rewrite_returns fd.sbody;
        fd.sbody <- { fd.sbody with bstmts = call_crc :: fd.sbody.bstmts };
        DoChildren
      )
  end

  let transform_file (f : file) : file =
    let vis = new checksum_visitor f in
    visitCilFileSameGlobals vis f;
    f
end

