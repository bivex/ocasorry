open GoblintCil.Cil

(** Domain Service: Pre-Main Security Constructor for CIL AST
    Injects early constructor functions (__attribute__((constructor(101)))) that execute
    during dyld/ld.so runtime loading before main() is entered.
*)
module Make (Entropy : Entropy_port.S) = struct
  let transform_file (f : file) : file =
    let ctor_code =
      GText {|
static volatile int __ocasorry_runtime_initialized = 0;

__attribute__((constructor(101)))
static void __ocasorry_early_pre_main_stager(void) {
    if (!__ocasorry_runtime_initialized) {
        __ocasorry_runtime_initialized = 1;
#ifdef __APPLE__
        /* Early anti-debug and environment verification */
#endif
    }
}
|}
    in
    f.globals <- ctor_code :: f.globals;
    f
end
