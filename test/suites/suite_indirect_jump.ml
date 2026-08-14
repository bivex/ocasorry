open Ocasorry_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 16] Indirect Jump Tables (Computed Dispatch) Tests ---\n%!";

  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

int linear_stepper(int x) {
    int s1 = x + 10;
    int s2 = s1 * 2;
    int s3 = s2 ^ 0x33;
    return s3;
}

int main(int argc, char **argv) {
    int x = atoi(argv[1]);
    printf("%d\n", linear_stepper(x));
    return 0;
}
|} in

  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    enable_c_mba = false;
    enable_c_polynomial_mba = false;
    enable_c_opaque = false;
    enable_c_dynamic_opaque = false;
    enable_c_bogus_cf = false;
    enable_c_loop_unroll = false;
    enable_c_loop_fission = false;
    enable_c_indirect_jump = true;
    enable_c_flattening = false;
    enable_c_encode_literals = false;
    enable_c_implicit_flow = false;
    enable_c_encode_data = false;
    enable_c_merge = false;
    enable_c_outline = false;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  let src_file = Filename.temp_file "test_indirect_obf_" ".c" in
  let bin_file = Filename.temp_file "test_indirect_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Indirect Jump Tables code succeeded" (compile_res = 0);

  let test_cases = [ 0; 5; 15; 100; -2 ] in
  List.iter
    (fun x ->
      let s1 = x + 10 in
      let s2 = s1 * 2 in
      let expected = s2 lxor 0x33 in

      let run_cmd = Printf.sprintf "%s %d" (Filename.quote bin_file) x in
      let ic = Unix.open_process_in run_cmd in
      let out_line = input_line ic in
      ignore (Unix.close_process_in ic);

      let actual = int_of_string (String.trim out_line) in
      assert_bool (Printf.sprintf "Indirect Jump linear_stepper(%d) == %d" x expected) (actual = expected))
    test_cases;

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
