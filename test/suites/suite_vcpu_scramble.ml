open Vectis_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 43] Polymorphic VCPU Context & Struct Scrambling Tests ---\n%!";

  let c_code = {|
int calc_scrambled_vcpu(int x) {
    int res = x + 10;
    return res;
}

int main(int argc, char **argv) {
    int x = 15;
    int res = calc_scrambled_vcpu(x);
    return (res == 256) ? 0 : 1;
}
|} in

  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    Obfuscate_c_source_usecase.default_c_config with
    enable_c_mba = false;
    enable_c_opaque = false;
    enable_c_flattening = false;
    enable_c_encode_literals = false;
    enable_c_encode_data = false;
    enable_c_vcpu_scramble = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Scrambled struct __vcpu_state generated"
    (try ignore (Str.search_forward (Str.regexp "struct __vcpu_state_") obfuscated_c 0); true with _ -> false);

  assert_bool "Padding fields injected into VCPU struct"
    (try ignore (Str.search_forward (Str.regexp "__pad_") obfuscated_c 0); true with _ -> false);

  let src_file = Filename.temp_file "test_vcpuscramble_obf_" ".c" in
  let bin_file = Filename.temp_file "test_vcpuscramble_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Scrambled VCPU struct succeeded" (compile_res = 0);

  let run_cmd1 = Printf.sprintf "%s" (Filename.quote bin_file) in
  let ret1 = Sys.command run_cmd1 in
  assert_bool "Scrambled VCPU struct execution calc_scrambled_vcpu(15) succeeded (Exit 0)" (ret1 = 0);

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
