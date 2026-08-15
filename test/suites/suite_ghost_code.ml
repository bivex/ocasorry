open Vectis_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 46] Ghost Code Injection (Null-Ring Compensation) Tests ---\n%!";

  let c_code = {|
int calc_ghost_comp(int x) {
    int a = x * 2;
    int b = a + 10;
    return b;
}

int main(int argc, char **argv) {
    /* x = 20 -> a = 40 -> b = 50 */
    return calc_ghost_comp(20);
}
|} in

  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    Obfuscate_c_source_usecase.default_c_config with
    enable_c_mba = false;
    enable_c_opaque = false;
    enable_c_flattening = false;
    enable_c_encode_literals = false;
    enable_c_encode_data = false;
    enable_c_ghost_code = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  let src_file = Filename.temp_file "test_ghost_obf_" ".c" in
  let bin_file = Filename.temp_file "test_ghost_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Ghost Code succeeded" (compile_res = 0);

  let run_cmd1 = Printf.sprintf "%s" (Filename.quote bin_file) in
  let ret1 = Sys.command run_cmd1 in
  assert_bool "Ghost Code Null-Ring execution calc_ghost_comp(20) == 50" (ret1 = 50);

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
