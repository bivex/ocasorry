open Ocasorry_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 6] Variable Splitting & Data Encoding (EncodeData) ---\n%!";

  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

int calc_complex(int a, int b) {
    int counter = 0;
    int accumulator = a * 3;
    counter = accumulator + b;
    accumulator = counter ^ 0x1234;
    return accumulator;
}

int main(int argc, char **argv) {
    int a = atoi(argv[1]);
    int b = atoi(argv[2]);
    printf("%d\n", calc_complex(a, b));
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
    enable_c_indirect_jump = false;
    enable_c_flattening = false;
    enable_c_encode_literals = false;
    enable_c_implicit_flow = false;
    enable_c_encode_data = true;
    enable_c_merge = false;
    enable_c_outline = false;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Local variables are split into _s1 and _s2 components"
    (try ignore (Str.search_forward (Str.regexp "_s1") obfuscated_c 0); true with _ -> false);

  let src_file = Filename.temp_file "test_split_obf_" ".c" in
  let bin_file = Filename.temp_file "test_split_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Variable Splitting code succeeded" (compile_res = 0);

  let test_inputs = [ (10, 20); (55, 33); (1234, 5678); (0, 0) ] in
  List.iter
    (fun (a, b) ->
      let acc1 = a * 3 in
      let cnt1 = acc1 + b in
      let expected = cnt1 lxor 0x1234 in

      let run_cmd = Printf.sprintf "%s %d %d" (Filename.quote bin_file) a b in
      let ic = Unix.open_process_in run_cmd in
      let out = input_line ic in
      ignore (Unix.close_process_in ic);

      let actual = int_of_string (String.trim out) in
      assert_bool
        (Printf.sprintf "Variable Splitting execution calc_complex(%d, %d) == %d (actual: %d)" a b expected actual)
        (actual = expected))
    test_inputs;

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
