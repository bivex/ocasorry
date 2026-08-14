open Ocasorry_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 51] Loop to Tail-Recursion Algorithmic Morphing Tests ---\n%!";

  let c_code = {|
int calc_loop_target(int x) {
    int acc = 0;
    for (int i = 0; i < 10; i++) {
        acc += x;
    }
    return acc;
}

int main(int argc, char **argv) {
    /* x = 5 -> acc calculated by recursive function */
    int res = calc_loop_target(5);
    return (res > 0) ? 0 : 1;
}
|} in

  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    Obfuscate_c_source_usecase.default_c_config with
    enable_c_mba = false;
    enable_c_opaque = false;
    enable_c_flattening = false;
    enable_c_encode_literals = false;
    enable_c_encode_data = false;
    enable_c_loop_to_recursion = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Recursive helper function __ocasorry_rec_iter injected"
    (try ignore (Str.search_forward (Str.regexp "__ocasorry_rec_iter") obfuscated_c 0); true with _ -> false);

  let src_file = Filename.temp_file "test_loop2rec_obf_" ".c" in
  let bin_file = Filename.temp_file "test_loop2rec_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Loop-to-Recursion morphed code succeeded" (compile_res = 0);

  let run_cmd1 = Printf.sprintf "%s" (Filename.quote bin_file) in
  let ret1 = Sys.command run_cmd1 in
  assert_bool "Loop-to-Recursion execution calc_loop_target(5) succeeded (Exit 0)" (ret1 = 0);

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
