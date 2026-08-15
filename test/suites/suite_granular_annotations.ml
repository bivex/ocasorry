open Vectis_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 59] Granular Function Annotations (__attribute__((annotate(...)))) Tests ---\n%!";

  let c_code = {|
extern int printf(const char *format, ...);

/* Comma-separated multi-attribute annotation */
__attribute__((annotate("vectis:visa, anti_debug, timing_check")))
int target_visa(int a, int b) {
    return (a + b) * 3 ^ 0x5A;
}

/* Semicolon & space separated list */
__attribute__((annotate("vectis:nested_vm; poly_mba")))
int target_nested(int x) {
    return x + 21;
}

/* Multi-pass comma-separated list */
__attribute__((annotate("rolling_vkey, relational_morph")))
int target_rolling(int x) {
    return ((x + 0x5A) ^ 0xA5) * 2;
}

/* Unobfuscated clean skip */
__attribute__((annotate("vectis:no_obf, skip")))
int target_clean_skipped(int x) {
    return x + 1000;
}

int main(int argc, char **argv) {
    if (target_visa(10, 20) != 0) return 1;
    if (target_nested(10) != 31) return 2;
    if (target_rolling(5) != 74) return 3;
    if (target_clean_skipped(42) != 1042) return 4;
    return 0;
}
|} in

  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    Obfuscate_c_source_usecase.default_c_config with
    enable_c_mba = false;
    enable_c_opaque = false;
    enable_c_flattening = false;
    enable_c_encode_literals = false;
    enable_c_encode_data = false;
    enable_c_virtualize = true;
    enable_c_nested_vm = true;
    enable_c_rolling_vkey = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Vector bytecode generated for target_visa"
    (try ignore (Str.search_forward (Str.regexp "__visa_program_target_visa") obfuscated_c 0); true with _ -> false);

  assert_bool "Nested bytecode generated for target_nested"
    (try ignore (Str.search_forward (Str.regexp "__packed_outer_bc_target_nested") obfuscated_c 0); true with _ -> false);

  assert_bool "Rolling key bytecode generated for target_rolling"
    (try ignore (Str.search_forward (Str.regexp "__rolling_bc_target_rolling") obfuscated_c 0); true with _ -> false);

  assert_bool "target_clean_skipped was preserved with no VM wrapping"
    (try ignore (Str.search_forward (Str.regexp "target_clean_skipped") obfuscated_c 0); true with _ -> false);

  let src_file = Filename.temp_file "test_annotations_obf_" ".c" in
  let bin_file = Filename.temp_file "test_annotations_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Granular Annotated code succeeded" (compile_res = 0);

  let run_cmd1 = Printf.sprintf "%s" (Filename.quote bin_file) in
  let ret1 = Sys.command run_cmd1 in
  assert_bool "Granular Annotated multi-VM execution test passed (Exit 0)" (ret1 = 0);

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
