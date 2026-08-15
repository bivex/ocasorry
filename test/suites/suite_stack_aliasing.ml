open Vectis_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 49] Stack Memory Aliasing (S-Box) Tests ---\n%!";

  let c_code = {|
int calc_stack_aliased(int x) {
    return x + 10;
}

int main(int argc, char **argv) {
    /* x = 20: (20 + 42) ^ 100 = 62 ^ 100 = 90 */
    return calc_stack_aliased(20);
}
|} in

  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    Obfuscate_c_source_usecase.default_c_config with
    enable_c_mba = false;
    enable_c_opaque = false;
    enable_c_flattening = false;
    enable_c_encode_literals = false;
    enable_c_encode_data = false;
    enable_c_stack_aliasing = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "S-Box permuted stack frame __stack_sbox injected"
    (try ignore (Str.search_forward (Str.regexp "__stack_sbox") obfuscated_c 0); true with _ -> false);

  let src_file = Filename.temp_file "test_stackalias_obf_" ".c" in
  let bin_file = Filename.temp_file "test_stackalias_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Stack Memory Aliased code succeeded" (compile_res = 0);

  let run_cmd1 = Printf.sprintf "%s" (Filename.quote bin_file) in
  let ret1 = Sys.command run_cmd1 in
  assert_bool "Stack Memory Aliased execution calc_stack_aliased(20) == 90" (ret1 = 90);

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
