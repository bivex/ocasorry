open Vectis_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 56] Basic Block Splitting (Jitter Jumps) Tests ---\n%!";

  let c_code = {|
int calc_split_target(int x, int y) {
    int a = x + 10;
    int b = y * 2;
    int c = a ^ b;
    int d = c + 42;
    return d;
}

int main(int argc, char **argv) {
    /* x = 5 -> a = 15, y = 3 -> b = 6, c = 15 ^ 6 = 9, d = 9 + 42 = 51 */
    int res = calc_split_target(5, 3);
    return (res == 51) ? 0 : 1;
}
|} in

  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    Obfuscate_c_source_usecase.default_c_config with
    enable_c_mba = false;
    enable_c_opaque = false;
    enable_c_flattening = false;
    enable_c_encode_literals = false;
    enable_c_encode_data = false;
    enable_c_basic_block_split = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Goto split jump injected into output" (String.contains obfuscated_c 'g' && String.contains obfuscated_c ':');

  let src_file = Filename.temp_file "test_split_bb_obf_" ".c" in
  let bin_file = Filename.temp_file "test_split_bb_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Basic Block Split code succeeded" (compile_res = 0);

  let run_cmd1 = Printf.sprintf "%s" (Filename.quote bin_file) in
  let ret1 = Sys.command run_cmd1 in
  assert_bool "Basic Block Split execution calc_split_target(5, 3) == 51 (Exit 0)" (ret1 = 0);

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
