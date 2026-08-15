open Vectis_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 55] Floating-Point Mixed Boolean-Arithmetic (FLOB Lifting) Tests ---\n%!";

  let c_code = {|
double calc_floating_point(double a, double b) {
    double sum = a + b;
    double diff = sum - 12.5;
    return diff;
}

int main(int argc, char **argv) {
    /* a = 100.5, b = 50.25 -> sum = 150.75 -> diff = 138.25 */
    double res = calc_floating_point(100.5, 50.25);
    /* Check precision within 0.01 tolerance */
    double diff = (res > 138.25) ? (res - 138.25) : (138.25 - res);
    return (diff < 0.01) ? 0 : 1;
}
|} in

  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    Obfuscate_c_source_usecase.default_c_config with
    enable_c_mba = false;
    enable_c_opaque = false;
    enable_c_flattening = false;
    enable_c_encode_literals = false;
    enable_c_encode_data = false;
    enable_c_float_mba = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  let src_file = Filename.temp_file "test_float_mba_obf_" ".c" in
  let bin_file = Filename.temp_file "test_float_mba_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Float MBA code succeeded" (compile_res = 0);

  let run_cmd1 = Printf.sprintf "%s" (Filename.quote bin_file) in
  let ret1 = Sys.command run_cmd1 in
  assert_bool "Float MBA execution calc_floating_point(100.5, 50.25) == 138.25 (Exit 0)" (ret1 = 0);

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
