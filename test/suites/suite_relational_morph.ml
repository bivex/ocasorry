open Vectis_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 58] Relational Boundary & Comparison Morphing Tests ---\n%!";

  let c_code = {|
int test_relational(int a, int b) {
    int score = 0;
    if (a == b) score += 10;
    if (a != b) score += 20;
    if (a < b)  score += 30;
    if (a > b)  score += 40;
    if (a <= b) score += 50;
    if (a >= b) score += 60;
    int safe = a / (b + 1);
    return score + safe;
}

int main(int argc, char **argv) {
    /* a = 5, b = 10:
       a != b (+20), a < b (+30), a <= b (+50), safe = 5 / 11 = 0 -> score = 100 */
    int r1 = test_relational(5, 10);
    if (r1 != 100) return 1;

    /* a = 10, b = 10:
       a == b (+10), a <= b (+50), a >= b (+60), safe = 10 / 11 = 0 -> score = 120 */
    int r2 = test_relational(10, 10);
    if (r2 != 120) return 2;

    /* a = 20, b = 5:
       a != b (+20), a > b (+40), a >= b (+60), safe = 20 / 6 = 3 -> score = 123 */
    int r3 = test_relational(20, 5);
    if (r3 != 123) return 3;

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
    enable_c_relational_morph = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  let src_file = Filename.temp_file "test_rel_morph_obf_" ".c" in
  let bin_file = Filename.temp_file "test_rel_morph_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Relational Morph code succeeded" (compile_res = 0);

  let run_cmd1 = Printf.sprintf "%s" (Filename.quote bin_file) in
  let ret1 = Sys.command run_cmd1 in
  assert_bool "Relational Morph execution test passed (Exit 0)" (ret1 = 0);

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
