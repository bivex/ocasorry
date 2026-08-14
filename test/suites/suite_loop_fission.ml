open Ocasorry_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 15] Loop Fission & Fusion Tests ---\n%!";

  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

int dual_accumulator_loop(int n) {
    int sum_a = 0;
    int sum_b = 0;
    int i = 0;
    while (i < n) {
        sum_a = sum_a + (i * 2);
        sum_b = sum_b + (i * 3);
        i = i + 1;
    }
    return sum_a + sum_b;
}

int main(int argc, char **argv) {
    int n = atoi(argv[1]);
    printf("%d\n", dual_accumulator_loop(n));
    return 0;
}
|} in

  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    Obfuscate_c_source_usecase.default_c_config with
    enable_c_mba = false;
    enable_c_opaque = false;
    enable_c_loop_fission = true;
    enable_c_flattening = false;
    enable_c_encode_literals = false;
    enable_c_encode_data = false;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  let src_file = Filename.temp_file "test_fission_obf_" ".c" in
  let bin_file = Filename.temp_file "test_fission_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Loop Fission code succeeded" (compile_res = 0);

  let test_cases = [ 5; 10; 20 ] in
  List.iter
    (fun n ->
      let rec calc_dual sa sb i =
        if i >= n then sa + sb else calc_dual (sa + (i * 2)) (sb + (i * 3)) (i + 1)
      in
      let expected = calc_dual 0 0 0 in

      let run_cmd = Printf.sprintf "%s %d" (Filename.quote bin_file) n in
      let ic = Unix.open_process_in run_cmd in
      let out_line = input_line ic in
      ignore (Unix.close_process_in ic);

      let actual = int_of_string (String.trim out_line) in
      assert_bool (Printf.sprintf "Loop Fission dual_accumulator_loop(%d) == %d" n expected) (actual = expected))
    test_cases;

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
