open Ocasorry_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 57] Decentralized Tree Dispatcher & Decoy Hub Tests ---\n%!";

  let c_code = {|
int calc_state_machine(int state, int val) {
    int res = 0;
    switch (state) {
        case 1: res = val + 10; break;
        case 2: res = val * 2; break;
        case 3: res = val ^ 0x5A; break;
        case 4: res = val - 5; break;
        default: res = val; break;
    }
    return res;
}

int main(int argc, char **argv) {
    /* state = 1 -> 5 + 10 = 15 */
    if (calc_state_machine(1, 5) != 15) return 1;
    /* state = 2 -> 5 * 2 = 10 */
    if (calc_state_machine(2, 5) != 10) return 2;
    /* state = 3 -> 5 ^ 0x5A = 95 */
    if (calc_state_machine(3, 5) != 95) return 3;
    /* state = 4 -> 5 - 5 = 0 */
    if (calc_state_machine(4, 5) != 0) return 4;
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
    enable_c_decentralized_disp = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Decoy hub state variable injected into output"
    (try ignore (Str.search_forward (Str.regexp "__decoy_hub_state") obfuscated_c 0); true with _ -> false);

  let src_file = Filename.temp_file "test_decent_disp_obf_" ".c" in
  let bin_file = Filename.temp_file "test_decent_disp_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Decentralized Dispatcher code succeeded" (compile_res = 0);

  let run_cmd1 = Printf.sprintf "%s" (Filename.quote bin_file) in
  let ret1 = Sys.command run_cmd1 in
  assert_bool "Decentralized Dispatcher execution test passed (Exit 0)" (ret1 = 0);

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
