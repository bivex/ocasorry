open Vectis_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 30] Function Inlining (Inline) Tests ---\n%!";

  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

int helper_add_constant(int val) {
    return val + 42;
}

int calculate_inlined(int x) {
    int res = helper_add_constant(x);
    return res;
}

int main(int argc, char **argv) {
    int x = atoi(argv[1]);
    printf("%d\n", calculate_inlined(x));
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
    enable_c_inline = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  let src_file = Filename.temp_file "test_inline_obf_" ".c" in
  let bin_file = Filename.temp_file "test_inline_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Inlined code succeeded" (compile_res = 0);

  let test_cases = [ (10, 52); (0, 42); (100, 142); (-5, 37) ] in
  List.iter
    (fun (x, expected) ->
      let run_cmd = Printf.sprintf "%s %d" (Filename.quote bin_file) x in
      let ic = Unix.open_process_in run_cmd in
      let out_line = input_line ic in
      ignore (Unix.close_process_in ic);

      let actual = int_of_string (String.trim out_line) in
      assert_bool (Printf.sprintf "Function Inlining calculate_inlined(%d) == %d" x expected) (actual = expected))
    test_cases;

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
