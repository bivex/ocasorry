open Vectis_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 52] Instruction Permutation (Def-Use Scheduling) Tests ---\n%!";

  let c_code = {|
int calc_permuted_order(int x) {
    int a = x + 10;
    int b = 42;
    int c = 100;
    int d = a + b + c;
    return d;
}

int main(int argc, char **argv) {
    /* x = 5: a = 15, b = 42, c = 100 -> d = 157 */
    int res = calc_permuted_order(5);
    return (res == 157) ? 0 : 1;
}
|} in

  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    Obfuscate_c_source_usecase.default_c_config with
    enable_c_mba = false;
    enable_c_opaque = false;
    enable_c_flattening = false;
    enable_c_encode_literals = false;
    enable_c_encode_data = false;
    enable_c_instruction_permute = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  let src_file = Filename.temp_file "test_permute_obf_" ".c" in
  let bin_file = Filename.temp_file "test_permute_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Instruction Permuted code succeeded" (compile_res = 0);

  let run_cmd1 = Printf.sprintf "%s" (Filename.quote bin_file) in
  let ret1 = Sys.command run_cmd1 in
  assert_bool "Instruction Permuted execution calc_permuted_order(5) == 157 (Exit 0)" (ret1 = 0);

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
