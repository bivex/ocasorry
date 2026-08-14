open Ocasorry_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 47] Live Range Splitting Tests ---\n%!";

  let c_code = {|
int calc_split_range(int x) {
    int val = x + 5;
    int res = val * 3;
    return res;
}

int main(int argc, char **argv) {
    /* x = 10 -> val = 15 -> res = 45 */
    return calc_split_range(10);
}
|} in

  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    Obfuscate_c_source_usecase.default_c_config with
    enable_c_mba = false;
    enable_c_opaque = false;
    enable_c_flattening = false;
    enable_c_encode_literals = false;
    enable_c_encode_data = false;
    enable_c_live_range_split = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Phase variable _phase2 generated"
    (try ignore (Str.search_forward (Str.regexp "_phase2") obfuscated_c 0); true with _ -> false);

  let src_file = Filename.temp_file "test_liverange_obf_" ".c" in
  let bin_file = Filename.temp_file "test_liverange_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Live Range Split code succeeded" (compile_res = 0);

  let run_cmd1 = Printf.sprintf "%s" (Filename.quote bin_file) in
  let ret1 = Sys.command run_cmd1 in
  assert_bool "Live Range Split execution calc_split_range(10) == 45" (ret1 = 45);

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
