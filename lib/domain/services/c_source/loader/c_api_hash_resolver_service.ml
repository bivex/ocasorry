open GoblintCil.Cil

(** Domain Service: Dynamic POSIX API Hashing for CIL AST
    Hides external library function names from import tables (nm, otool, readelf)
    by resolving symbols at runtime via compile-time CRC32 hashes and dlsym.
*)
module Make (Entropy : Entropy_port.S) = struct
  let crc32_hash (s : string) : int64 =
    let crc = ref 0xFFFFFFFFL in
    for i = 0 to String.length s - 1 do
      let b = Int64.of_int (Char.code s.[i]) in
      crc := Int64.logxor !crc b;
      for _ = 0 to 7 do
        let mask = Int64.logand !crc 1L in
        crc := Int64.shift_right_logical !crc 1;
        if mask <> 0L then
          crc := Int64.logxor !crc 0xEDB88320L
      done
    done;
    Int64.logand (Int64.lognot !crc) 0xFFFFFFFFL

  class api_resolver_visitor (file : file) (target_symbols : (string, int64) Hashtbl.t) = object
    inherit nopCilVisitor

    val mutable helper_injected = false

    method! vfunc (fd : fundec) : fundec visitAction =
      if String.starts_with ~prefix:"__ocasorry_" fd.svar.vname then SkipChildren
      else (
        if not helper_injected then (
          helper_injected <- true;
          let resolver_helper =
            GText {|
#include <dlfcn.h>
#include <stdint.h>
#include <string.h>

static uint32_t __ocasorry_calc_crc32(const char *s) {
    uint32_t crc = 0xFFFFFFFF;
    while (*s) {
        crc ^= (uint32_t)(unsigned char)(*s++);
        for (int i = 0; i < 8; i++) {
            crc = (crc >> 1) ^ ((crc & 1) ? 0xEDB88320 : 0);
        }
    }
    return ~crc;
}

static void *__ocasorry_resolve_symbol_hash(uint32_t target_hash, const char *name) {
    void *h = dlopen(0, RTLD_LAZY);
    if (!h) return 0;
    if (name && __ocasorry_calc_crc32(name) == target_hash) {
        return dlsym(h, name);
    }
    return 0;
}
|}
          in
          file.globals <- resolver_helper :: file.globals
        );
        DoChildren
      )

    method! vstmt (s : stmt) : stmt visitAction =
      match s.skind with
      | Instr [ Call (ret_opt, Lval (Var fn_var, NoOffset), args, loc, eloc) ] ->
          if Hashtbl.mem target_symbols fn_var.vname then (
            let hash_val = Hashtbl.find target_symbols fn_var.vname in
            let resolve_fn =
              makeGlobalVar "__ocasorry_resolve_symbol_hash"
                (TFun (voidPtrType, Some [ ("hash", uintType, []); ("name", charPtrType, []) ], false, []))
            in
            let tmp_ptr = makeVarinfo false ("__resolved_" ^ fn_var.vname) voidPtrType in
            let hash_exp = kinteger64 IUInt hash_val in
            let call_resolve =
              Call (Some (var tmp_ptr), Lval (var resolve_fn), [ hash_exp; mkString fn_var.vname ], loc, eloc)
            in
            let fn_ptr_type = TPtr (fn_var.vtype, []) in
            let cast_fn_ptr = CastE (fn_ptr_type, Lval (var tmp_ptr)) in
            let indirect_call = Call (ret_opt, Lval (Mem cast_fn_ptr, NoOffset), args, loc, eloc) in
            ChangeTo (mkStmt (Block (mkBlock [ mkStmtOneInstr call_resolve; mkStmtOneInstr indirect_call ])))
          ) else DoChildren
      | _ -> DoChildren
  end

  let transform_file (f : file) : file =
    let defined_funcs = Hashtbl.create 32 in
    List.iter
      (function
        | GFun (fd, _) -> Hashtbl.add defined_funcs fd.svar.vname true
        | _ -> ())
      f.globals;

    let target_symbols = Hashtbl.create 32 in
    List.iter
      (function
        | GVarDecl (v, _) when not (Hashtbl.mem defined_funcs v.vname)
                               && not (String.starts_with ~prefix:"__" v.vname)
                               && (v.vname = "printf" || v.vname = "atoi" || v.vname = "exit" || v.vname = "malloc" || v.vname = "free") ->
            Hashtbl.add target_symbols v.vname (crc32_hash v.vname)
        | _ -> ())
      f.globals;

    if Hashtbl.length target_symbols > 0 then (
      let vis = new api_resolver_visitor f target_symbols in
      visitCilFileSameGlobals vis f;
      f
    ) else f
end
