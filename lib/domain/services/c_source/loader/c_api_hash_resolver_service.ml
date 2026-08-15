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

/* Hash-only resolver: no plaintext symbol name ever leaves the binary in call sites.
   The resolver scans a static candidate table keyed by CRC32, resolving purely by hash. */
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

static void *__ocasorry_resolve_symbol_hash(uint32_t target_hash) {
    /* Candidate symbol names stored as XOR-obfuscated byte arrays (key=0xA5).
       No plaintext strings appear in __cstring / __data sections.
       Sentinel 0xA5 = (0x00 ^ 0xA5) marks end of each name. */
    static const unsigned char __c0[] = {0xd5,0xd7,0xcc,0xcb,0xd1,0xc3,0xA5}; /* printf */
    static const unsigned char __c1[] = {0xd5,0xd0,0xd1,0xd6,0xA5};           /* puts */
    static const unsigned char __c2[] = {0xc0,0xdd,0xcc,0xd1,0xA5};           /* exit */
    static const unsigned char __c3[] = {0xc8,0xc4,0xc9,0xc9,0xca,0xc6,0xA5};/* malloc */
    static const unsigned char __c4[] = {0xc3,0xd7,0xc0,0xc0,0xA5};          /* free */
    static const unsigned char __c5[] = {0xc8,0xc0,0xc8,0xd6,0xc0,0xd1,0xA5};/* memset */
    static const unsigned char __c6[] = {0xc8,0xc0,0xc8,0xc6,0xd5,0xdc,0xA5};/* memcpy */
    static const unsigned char __c7[] = {0xd6,0xd1,0xd7,0xc9,0xc0,0xcb,0xA5};/* strlen */
    static const unsigned char __c8[] = {0xc3,0xca,0xd5,0xc0,0xcb,0xA5};     /* fopen */
    static const unsigned char __c9[] = {0xd6,0xd5,0xd7,0xcc,0xcb,0xd1,0xc3,0xA5};       /* sprintf */
    static const unsigned char __ca[] = {0xd6,0xcb,0xd5,0xd7,0xcc,0xcb,0xd1,0xc3,0xA5};  /* snprintf */
    static const unsigned char __cb[] = {0xc4,0xc7,0xca,0xd7,0xd1,0xA5};     /* abort */

    static const unsigned char * const __enc[] = {
        __c0, __c1, __c2, __c3, __c4, __c5, __c6, __c7, __c8, __c9, __ca, __cb, 0
    };

    for (int i = 0; __enc[i] != 0; i++) {
        /* Decode name on the stack at runtime — never stored as plaintext */
        char name[32];
        int j = 0;
        while (__enc[i][j] != 0xA5 && j < 31) {
            name[j] = (char)(__enc[i][j] ^ 0xA5);
            j++;
        }
        name[j] = '\0';

        if (__ocasorry_calc_crc32(name) == target_hash) {
#ifdef RTLD_DEFAULT
            void *sym = dlsym(RTLD_DEFAULT, name);
#else
            void *sym = dlsym((void*)-2, name);
#endif
            if (sym) return sym;
            void *h = dlopen(0, 1);
            if (h) return dlsym(h, name);
        }
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
              (TFun (voidPtrType, Some [ ("target_hash", uintType, []) ], false, []))
          in
          
          let var_name = Printf.sprintf "__resolved_%s" fn_var.vname in
          let resolved_ptr =
            match List.find_opt (fun (v : varinfo) -> v.vname = var_name) fd.slocals with
            | Some existing -> existing
            | None -> makeLocalVar fd var_name voidPtrType
          in

          let call_resolve =
            Call (Some (var resolved_ptr), Lval (var resolve_fn),
                  [ kinteger64 IUInt hash_val ], loc, loc)
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
