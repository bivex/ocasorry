open Ocasorry_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 44] In-Memory Ephemeral Payload Unpacking Tests ---\n%!";

  let c_code = {|
extern int printf(const char *format, ...);

int calc_ephemeral_func(int x) {
    int res = x + 100;
    return res;
}

int main(int argc, char **argv) {
    int x = 20;
    int res = calc_ephemeral_func(x);
    printf("%d\n", res);
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
    enable_c_ephemeral_payload = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Ephemeral memory allocator __ocasorry_alloc_ephemeral_page injected"
    (try ignore (Str.search_forward (Str.regexp "__ocasorry_alloc_ephemeral_page") obfuscated_c 0); true with _ -> false);

  assert_bool "Ephemeral memory wiper __ocasorry_free_ephemeral_page injected"
    (try ignore (Str.search_forward (Str.regexp "__ocasorry_free_ephemeral_page") obfuscated_c 0); true with _ -> false);

  let src_file = Filename.temp_file "test_ephemeral_obf_" ".c" in
  let bin_file = Filename.temp_file "test_ephemeral_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Ephemeral Payload code succeeded" (compile_res = 0);

  let run_cmd1 = Printf.sprintf "%s" (Filename.quote bin_file) in
  let ic = Unix.open_process_in run_cmd1 in
  let out = input_line ic in
  ignore (Unix.close_process_in ic);
  let res_val = int_of_string (String.trim out) in
  assert_bool "Ephemeral Payload execution produced valid result" (res_val > 0);

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
