open Ocasorry_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 13] Bogus Control Flow (BCF Code Cloning & Mutation) Tests ---\n%!";

  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

int compute_bcf_target(int x, int y) {
    int a = x + 10;
    int b = y * 5;
    int c = a ^ b;
    return c;
}

int main(int argc, char **argv) {
    int x = atoi(argv[1]);
    int y = atoi(argv[2]);
    printf("%d\n", compute_bcf_target(x, y));
    return 0;
}
|} in

  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    Obfuscate_c_source_usecase.default_c_config with
    enable_c_mba = false;
    enable_c_opaque = false;
    enable_c_bogus_cf = true;
    enable_c_flattening = false;
    enable_c_encode_literals = false;
    enable_c_encode_data = false;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  let src_file = Filename.temp_file "test_bcf_obf_" ".c" in
  let bin_file = Filename.temp_file "test_bcf_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Bogus Control Flow code succeeded" (compile_res = 0);

  let test_cases = [ (10, 20); (0, 0); (5, 99); (-3, 15) ] in
  List.iter
    (fun (x, y) ->
      let a = x + 10 in
      let b = y * 5 in
      let expected = a lxor b in

      let run_cmd = Printf.sprintf "%s %d %d" (Filename.quote bin_file) x y in
      let ic = Unix.open_process_in run_cmd in
      let out_line = input_line ic in
      ignore (Unix.close_process_in ic);

      let actual = int_of_string (String.trim out_line) in
      assert_bool (Printf.sprintf "BCF execution compute_bcf_target(%d, %d) == %d" x y expected) (actual = expected))
    test_cases;

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
