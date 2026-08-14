open Ocasorry_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 42] Stateful Rolling Bytecode Key Chain Tests ---\n%!";

  let c_code = {|
int calc_rolling_chain(int x) {
    int res = (x + 10) ^ 42;
    return res * 2;
}

int main(int argc, char **argv) {
    int x = 5;
    return calc_rolling_chain(x);
}
|} in

  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    Obfuscate_c_source_usecase.default_c_config with
    enable_c_mba = false;
    enable_c_opaque = false;
    enable_c_flattening = false;
    enable_c_encode_literals = false;
    enable_c_encode_data = false;
    enable_c_rolling_vkey = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Rolling bytecode array __rolling_bc generated"
    (try ignore (Str.search_forward (Str.regexp "__rolling_bc_") obfuscated_c 0); true with _ -> false);

  assert_bool "Stateful key evolution formula injected"
    (try ignore (Str.search_forward (Str.regexp "__vkey") obfuscated_c 0); true with _ -> false);

  let src_file = Filename.temp_file "test_rolling_obf_" ".c" in
  let bin_file = Filename.temp_file "test_rolling_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Rolling Keycode VM succeeded" (compile_res = 0);

  (* Expected: (5 + 10) ^ 42 = 15 ^ 42 = 37; 37 * 2 = 74 *)
  let run_cmd1 = Printf.sprintf "%s" (Filename.quote bin_file) in
  let ret1 = Sys.command run_cmd1 in
  assert_bool "Rolling VKey VM execution calc_rolling_chain(5) == 74" (ret1 = 74);

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
