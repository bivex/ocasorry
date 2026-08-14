open Ocasorry_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 45] Instruction Substitution Tests ---\n%!";

  let c_code = {|
int calc_subst(int a, int b) {
    int r1 = a + 1;
    int r2 = b - 1;
    int r3 = r1 ^ r2;
    int r4 = r3 + b;
    return r4;
}

int main(int argc, char **argv) {
    /* a = 10, b = 5:
       r1 = 11
       r2 = 4
       r3 = 11 ^ 4 = 15
       r4 = 15 + 5 = 20
    */
    return calc_subst(10, 5);
}
|} in

  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    Obfuscate_c_source_usecase.default_c_config with
    enable_c_mba = false;
    enable_c_opaque = false;
    enable_c_flattening = false;
    enable_c_encode_literals = false;
    enable_c_encode_data = false;
    enable_c_instruction_subst = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  let src_file = Filename.temp_file "test_subst_obf_" ".c" in
  let bin_file = Filename.temp_file "test_subst_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Instruction Substituted code succeeded" (compile_res = 0);

  let run_cmd1 = Printf.sprintf "%s" (Filename.quote bin_file) in
  let ret1 = Sys.command run_cmd1 in
  assert_bool "Instruction Substitution calc_subst(10, 5) == 20" (ret1 = 20);

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
