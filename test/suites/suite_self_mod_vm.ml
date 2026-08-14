open Ocasorry_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 24] Self-Modifying Bytecode VM Tests ---\n%!";

  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

int calc_self_mod(int x) {
    int val = x;
    return val;
}

int main(int argc, char **argv) {
    int x = atoi(argv[1]);
    printf("%d\n", calc_self_mod(x));
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
    enable_c_self_mod_vm = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Self-Modifying bytecode array __self_mod_bc generated"
    (try ignore (Str.search_forward (Str.regexp "__self_mod_bc") obfuscated_c 0); true with _ -> false);

  let src_file = Filename.temp_file "test_sm_obf_" ".c" in
  let bin_file = Filename.temp_file "test_sm_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Self-Modifying VM code succeeded" (compile_res = 0);

  let test_cases = [ 10; 42; 0; 100 ] in
  List.iter
    (fun x ->
      let expected = x + 10 in (* 1 + 2 + 3 + 4 = 10 *)
      let run_cmd = Printf.sprintf "%s %d" (Filename.quote bin_file) x in
      let ic = Unix.open_process_in run_cmd in
      let out_line = input_line ic in
      ignore (Unix.close_process_in ic);

      let actual = int_of_string (String.trim out_line) in
      assert_bool (Printf.sprintf "Self-Modifying VM calc_self_mod(%d) == %d" x expected) (actual = expected))
    test_cases;

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
