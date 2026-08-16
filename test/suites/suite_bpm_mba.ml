open Vectis_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 71] Bit-Permutation MBA (BPM / Anti-DSE) ---\n%!";

  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

int bpm_math(int a, int b) {
    int sum = a + b;
    int xor_val = a ^ b;
    int and_val = a & b;
    int or_val  = a | b;
    int res = (sum ^ xor_val) + (and_val ^ or_val);
    return res;
}

int main(int argc, char **argv) {
    int a = atoi(argv[1]);
    int b = atoi(argv[2]);
    printf("%d\n", bpm_math(a, b));
    return 0;
}
|} in

  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    Obfuscate_c_source_usecase.default_c_config with
    enable_c_mba = false;
    enable_c_polynomial_mba = false;
    enable_c_bpm_mba = true;
    enable_c_opaque = false;
    enable_c_flattening = false;
    enable_c_encode_literals = false;
    enable_c_encode_data = false;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  let src_file = Filename.temp_file "test_bpm_obf_" ".c" in
  let bin_file = Filename.temp_file "test_bpm_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Bit-Permutation MBA (BPM) code succeeded" (compile_res = 0);

  let test_pairs = [
    (10, 20);
    (100, 200);
    (-50, 75);
    (1337, 4242);
    (0, 0);
    (99999, 12345);
  ] in

  List.iter
    (fun (a, b) ->
      let sum = a + b in
      let xor_val = a lxor b in
      let and_val = a land b in
      let or_val  = a lor b in
      let expected = (sum lxor xor_val) + (and_val lxor or_val) in

      let run_cmd = Printf.sprintf "%s %d %d" (Filename.quote bin_file) a b in
      let ic = Unix.open_process_in run_cmd in
      let out_line = input_line ic in
      ignore (Unix.close_process_in ic);

      let actual = int_of_string (String.trim out_line) in
      assert_bool
        (Printf.sprintf "Bit-Permutation MBA execution bpm_math(%d, %d) == %d (actual: %d)" a b expected actual)
        (actual = expected))
    test_pairs;


  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
