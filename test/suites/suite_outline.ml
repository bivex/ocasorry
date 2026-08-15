open Vectis_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 11] Function Outlining (Tigress Outline) Tests ---\n%!";

  let c_code = {|
extern int printf(const char *format, ...);
extern int atoi(const char *nptr);

int complex_step_processor(int x) {
    int step1 = x * 3;
    int step2 = step1 + 50;
    int step3 = step2 ^ 0x55;
    int step4 = step3 - 12;
    return step4;
}

int main(int argc, char **argv) {
    int x = atoi(argv[1]);
    printf("%d\n", complex_step_processor(x));
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
    enable_c_outline = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Outlined subroutine __outlined_complex_step_processor generated"
    (try ignore (Str.search_forward (Str.regexp "__outlined_complex_step_processor") obfuscated_c 0); true with _ -> false);

  let src_file = Filename.temp_file "test_outline_obf_" ".c" in
  let bin_file = Filename.temp_file "test_outline_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Outlined Functions code succeeded" (compile_res = 0);

  let test_cases = [ 10; 42; 100; -5; 0 ] in
  List.iter
    (fun x ->
      let step1 = x * 3 in
      let step2 = step1 + 50 in
      let step3 = step2 lxor 0x55 in
      let expected = step3 - 12 in

      let run_cmd = Printf.sprintf "%s %d" (Filename.quote bin_file) x in
      let ic = Unix.open_process_in run_cmd in
      let out_line = input_line ic in
      ignore (Unix.close_process_in ic);

      let actual = int_of_string (String.trim out_line) in
      assert_bool (Printf.sprintf "Outlined execution complex_step_processor(%d) == %d" x expected) (actual = expected))
    test_cases;

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
