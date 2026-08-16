open Vectis_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 44] In-Memory Native Ephemeral JIT Compiler Tests ---\n%!";

  let c_code = {|
extern int printf(const char *format, ...);

__attribute__((annotate("vectis:ephemeral")))
int calc_arithmetic_jit(int x) {
    int a = x * 3;
    int b = (a ^ 0x5A) + 42;
    return b;
}

__attribute__((annotate("vectis:ephemeral")))
int calc_conditional_jit(int x) {
    if (x >= 50) {
        return x * 2;
    } else {
        return x + 10;
    }
}

int main(int argc, char **argv) {
    int v1 = calc_arithmetic_jit(15);
    int v2 = calc_conditional_jit(60);
    int v3 = calc_conditional_jit(20);
    printf("%d %d %d\n", v1, v2, v3);
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
    enable_c_ephemeral_payload = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Ephemeral memory allocator __vectis_alloc_ephemeral_page injected"
    (try ignore (Str.search_forward (Str.regexp "__vectis_alloc_ephemeral_page") obfuscated_c 0); true with _ -> false);

  assert_bool "Ephemeral memory wiper __vectis_free_ephemeral_page injected"
    (try ignore (Str.search_forward (Str.regexp "__vectis_free_ephemeral_page") obfuscated_c 0); true with _ -> false);

  let src_file = Filename.temp_file "test_ephemeral_obf_" ".c" in
  let bin_file = Filename.temp_file "test_ephemeral_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Native Ephemeral JIT code succeeded" (compile_res = 0);

  let run_cmd1 = Printf.sprintf "%s" (Filename.quote bin_file) in
  let ic = Unix.open_process_in run_cmd1 in
  let out = input_line ic in
  ignore (Unix.close_process_in ic);

  let parts = String.split_on_char ' ' (String.trim out) in
  let v1 = int_of_string (List.nth parts 0) in
  let v2 = int_of_string (List.nth parts 1) in
  let v3 = int_of_string (List.nth parts 2) in

  let expected_v1 = ((15 * 3) lxor 0x5A) + 42 in
  let expected_v2 = 60 * 2 in
  let expected_v3 = 20 + 10 in

  assert_bool (Printf.sprintf "Native JIT Arithmetic result: %d == %d" v1 expected_v1) (v1 = expected_v1);
  assert_bool (Printf.sprintf "Native JIT Conditional result 1: %d == %d" v2 expected_v2) (v2 = expected_v2);
  assert_bool (Printf.sprintf "Native JIT Conditional result 2: %d == %d" v3 expected_v3) (v3 = expected_v3);

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
