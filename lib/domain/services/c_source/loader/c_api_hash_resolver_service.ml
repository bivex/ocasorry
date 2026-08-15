open GoblintCil.Cil

(** Domain Service: Dynamic POSIX API Hashing for CIL AST
    Hides direct libc symbol imports (printf, puts, exit, malloc) behind runtime
    CRC32 hash resolution via dlsym/RTLD_DEFAULT.
*)
module Make (Entropy : Entropy_port.S) = struct
  let crc32 (str : string) : int64 =
    let crc = ref 0xFFFFFFFFL in
    for i = 0 to String.length str - 1 do
      let byte = Int64.of_int (Char.code str.[i]) in
      crc := Int64.logxor !crc byte;
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
    val mutable cur_fd : fundec option = None

    method! vfunc (fd : fundec) : fundec visitAction =
      if String.starts_with ~prefix:"__ocasorry_" fd.svar.vname
         || C_annotation_service.AnnotationHelper.should_skip_all fd then SkipChildren
      else (
        cur_fd <- Some fd;
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
    if (!name) return 0;
    if (__ocasorry_calc_crc32(name) == target_hash) {
#ifdef RTLD_DEFAULT
        void *sym = dlsym(RTLD_DEFAULT, name);
#else
        void *sym = dlsym((void*)-2, name);
#endif
        if (sym) return sym;
        void *h = dlopen(0, RTLD_LAZY);
        if (h) return dlsym(h, name);
    }
    return 0;
}
|}
          in
          file.globals <- resolver_helper :: file.globals
        );
        DoChildren
      )

    method! vinst (i : instr) : instr list visitAction =
      match i with
      | Call (ret_opt, Lval (Var fn_var, NoOffset), args, loc, _)
        when Hashtbl.mem target_symbols fn_var.vname && cur_fd <> None ->
          let fd = Option.get cur_fd in
          let hash_val = Hashtbl.find target_symbols fn_var.vname in
          let resolve_fn =
            makeGlobalVar "__ocasorry_resolve_symbol_hash"
              (TFun (voidPtrType, Some [ ("target_hash", uintType, []); ("name", charConstPtrType, []) ], false, []))
          in
          
          let var_name = Printf.sprintf "__resolved_%s" fn_var.vname in
          let resolved_ptr =
            match List.find_opt (fun (v : varinfo) -> v.vname = var_name) fd.slocals with
            | Some existing -> existing
            | None -> makeLocalVar fd var_name voidPtrType
          in

          let call_resolve =
            Call (Some (var resolved_ptr), Lval (var resolve_fn),
                  [ kinteger64 IUInt hash_val; mkString fn_var.vname ], loc, loc)
          in

          let target_fun_type = fn_var.vtype in
          let cast_fn_ptr = CastE (TPtr (target_fun_type, []), Lval (var resolved_ptr)) in
          let call_indirect =
            Call (ret_opt, Lval (Mem cast_fn_ptr, NoOffset), args, loc, loc)
          in

          ChangeTo [ call_resolve; call_indirect ]
      | _ -> DoChildren
  end

  let transform_file (f : file) : file =
    let targets = Hashtbl.create 16 in
    List.iter
      (fun name -> Hashtbl.add targets name (crc32 name))
      [ "printf"; "puts"; "exit"; "malloc"; "free" ];

    let vis = new api_resolver_visitor f targets in
    visitCilFileSameGlobals vis f;
    f
end
