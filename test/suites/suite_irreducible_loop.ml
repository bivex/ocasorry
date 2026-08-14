open Ocasorry_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 60] Irreducible Control-Flow Graph & Multi-Exit Loop Tests (arXiv:2604.13675v1) ---\n%!";

  let c_code = {|
extern int printf(const char *format, ...);

int calc_loop(int n) {
    int sum = 0;
    int i = 0;
    while (1) {
        if (i >= n) break;
        sum += (i * 3) ^ 0x5A;
        i++;
    }
    return sum;
}

int calc_for_loop(int limit) {
    int acc = 10;
    for (int k = 1; k <= limit; k++) {
        if (k == 5) {
            acc += 100;
        }
        acc = (acc * 2) - k;
    }
    return acc;
}

int main(int argc, char **argv) {
    if (calc_loop(5) != 440) return 1;
    if (calc_loop(0) != 0) return 2;
    if (calc_for_loop(3) != 69) return 3;
    if (calc_for_loop(6) != 920) return 4;
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
    enable_c_irreducible_loop = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Irreducible Entry A label injected into output"
    (try ignore (Str.search_forward (Str.regexp "__irred_entry_A_") obfuscated_c 0); true with _ -> false);

  assert_bool "Irreducible Entry B label injected into output"
    (try ignore (Str.search_forward (Str.regexp "__irred_entry_B_") obfuscated_c 0); true with _ -> false);

  assert_bool "Multi-Exit labels injected into output"
    (try ignore (Str.search_forward (Str.regexp "__irred_exit_1_") obfuscated_c 0); true with _ -> false);

  let src_file = Filename.temp_file "test_irred_obf_" ".c" in
  let bin_file = Filename.temp_file "test_irred_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Irreducible Loop code succeeded" (compile_res = 0);

  let run_cmd1 = Printf.sprintf "%s" (Filename.quote bin_file) in
  let ret1 = Sys.command run_cmd1 in
  assert_bool "Irreducible Loop multi-exit execution test passed (Exit 0)" (ret1 = 0);

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
