open Ocasorry_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 17] Lookup Table Arithmetic (LUT) Tests ---\n%!";

  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

int calc_lut_xor(int x) {
    int byte_val = x & 0xFF;
    int res = byte_val ^ 0x5A;
    return res;
}

int main(int argc, char **argv) {
    int x = atoi(argv[1]);
    printf("%d\n", calc_lut_xor(x));
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
    enable_c_lut = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Lookup table __lut_xor generated in static memory"
    (try ignore (Str.search_forward (Str.regexp "__lut_xor") obfuscated_c 0); true with _ -> false);

  let src_file = Filename.temp_file "test_lut_obf_" ".c" in
  let bin_file = Filename.temp_file "test_lut_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of LUT code succeeded" (compile_res = 0);

  let test_cases = [ 0; 42; 100; 255; 1337 ] in
  List.iter
    (fun x ->
      let expected = (x land 0xFF) lxor 0x5A in
      let run_cmd = Printf.sprintf "%s %d" (Filename.quote bin_file) x in
      let ic = Unix.open_process_in run_cmd in
      let out_line = input_line ic in
      ignore (Unix.close_process_in ic);

      let actual = int_of_string (String.trim out_line) in
      assert_bool (Printf.sprintf "LUT calc_lut_xor(%d) == %d" x expected) (actual = expected))
    test_cases;

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
