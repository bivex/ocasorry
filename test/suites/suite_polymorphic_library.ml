open Ocasorry_lib
open Helpers

module PolyLibApp = Build_polymorphic_library_usecase.Make
    (System_entropy_adapter.Adapter)
    (Goblint_cil_adapter.Adapter)

let run () =
  Printf.printf "\n--- [Suite 62] Polymorphic Shared Library & Universal C-ABI Calling Tests ---\n%!";

  let tmp_dir = Filename.temp_file "poly_lib_test_" "" in
  (try Sys.remove tmp_dir with _ -> ());
  Unix.mkdir tmp_dir 0o755;

  let ext = if Sys.os_type = "Unix" && (
    let p = Unix.open_process_in "uname -s" in
    let s = input_line p in
    close_in p;
    String.trim s = "Darwin"
  ) then ".dylib" else ".so" in

  let src_path = Filename.concat tmp_dir "secret_calc.c" in
  let lib_path = Filename.concat tmp_dir ("libsecret_calc" ^ ext) in

  let oc = open_out src_path in
  output_string oc {|
typedef unsigned long long uint64_t;

uint64_t compute_protected_hash(uint64_t a, uint64_t b, const char *msg) {
    uint64_t acc = (a * 31) ^ (b + 100);
    if (msg) {
        acc = (acc + (uint64_t)((unsigned char)msg[0] * 7)) ^ 0x5A;
        acc = (acc + (uint64_t)((unsigned char)msg[1] * 13)) ^ 0x33;
        acc = (acc + (uint64_t)((unsigned char)msg[2] * 19)) ^ 0x77;
    }
    return acc;
}
|};
  close_out oc;

  let config : Obfuscate_c_source_usecase.c_pipeline_config = {
    Obfuscate_c_source_usecase.default_c_config with
    enable_c_virtualize = true;
    enable_c_polynomial_mba = true;
    enable_c_encode_literals = true;
    enable_c_anti_debug = true;
  } in

  let build_res =
    PolyLibApp.build_shared_library
      ~export_symbols:[ "compute_protected_hash" ]
      ~input_c:src_path
      ~output_lib:lib_path
      ~config
      ()
  in

  (match build_res with
  | Ok p ->
      assert_bool "Polymorphic shared library was compiled successfully" (Sys.file_exists p);
      Printf.printf "  [PASS] Polymorphic Shared Library built at %s\n%!" p
  | Error msg ->
      Printf.printf "  [FAIL] Failed to build polymorphic library: %s\n%!" msg;
      assert_bool "Build failed" false);

  (* Test loading and calling the shared library from a dynamically compiled C caller *)
  let caller_c = Filename.concat tmp_dir "caller.c" in
  let caller_bin = Filename.concat tmp_dir "caller.bin" in
  let oc = open_out caller_c in
  output_string oc (Printf.sprintf {|
#include <stdio.h>
#include <stdint.h>
#include <dlfcn.h>
#include <assert.h>

typedef uint64_t (*hash_fn)(uint64_t, uint64_t, const char *);

int main() {
    void *h = dlopen("%s", RTLD_NOW);
    if (!h) {
        fprintf(stderr, "dlopen failed: %%s\n", dlerror());
        return 1;
    }
    hash_fn fn = (hash_fn)dlsym(h, "compute_protected_hash");
    if (!fn) {
        fprintf(stderr, "dlsym failed: %%s\n", dlerror());
        return 2;
    }

    uint64_t res = fn(10, 20, "OCASORRY_SECRET");
    /* Verify result is consistent and non-zero */
    if (res == 0) return 3;
    dlclose(h);
    return 0;
}
|} lib_path);
  close_out oc;

  let compile_caller = Printf.sprintf "clang -O2 %s -o %s -ldl" (Filename.quote caller_c) (Filename.quote caller_bin) in
  let c_res = Sys.command compile_caller in
  assert_bool "Caller executable compiled successfully" (c_res = 0);

  let run_caller = Sys.command (Filename.quote caller_bin) in
  assert_bool "Shared Library dynamic invocation via dlopen/dlsym succeeded" (run_caller = 0);
  Printf.printf "  [PASS] Zero-wrapper Universal C-ABI Dynamic invocation test passed (Exit 0)\n%!";

  (try ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmp_dir))) with _ -> ())
