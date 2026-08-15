open Vectis_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 21] Homomorphic Data Encoding Tests ---\n%!";

  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

int calc_homomorphic_sum(int a, int b) {
    int sum = a + b;
    int total = sum + 50;
    return total;
}

int main(int argc, char **argv) {
    int a = atoi(argv[1]);
    int b = atoi(argv[2]);
    printf("%d\n", calc_homomorphic_sum(a, b));
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
    enable_c_homomorphic = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  let src_file = Filename.temp_file "test_homo_obf_" ".c" in
  let bin_file = Filename.temp_file "test_homo_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Homomorphic Encoding code succeeded" (compile_res = 0);

  let test_cases = [ (10, 20); (100, 200); (0, 0); (-5, 15) ] in
  List.iter
    (fun (a, b) ->
      let expected = a + b + 50 in
      let run_cmd = Printf.sprintf "%s %d %d" (Filename.quote bin_file) a b in
      let ic = Unix.open_process_in run_cmd in
      let out_line = input_line ic in
      ignore (Unix.close_process_in ic);

      let actual = int_of_string (String.trim out_line) in
      assert_bool (Printf.sprintf "Homomorphic calc_homomorphic_sum(%d, %d) == %d" a b expected) (actual = expected))
    test_cases;

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
