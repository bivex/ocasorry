open Ocasorry_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 34] Source Directives Stripping Tests ---\n%!";

  let c_code = {|
#line 100 "secret_internal_source.c"
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

int compute_clean(int x) {
#line 105 "secret_internal_source.c"
    return x * 10;
}

int main(int argc, char **argv) {
    int x = atoi(argv[1]);
    printf("%d\n", compute_clean(x));
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
    enable_c_strip_directives = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Original filename 'secret_internal_source.c' stripped from output"
    (try ignore (Str.search_forward (Str.regexp "secret_internal_source.c") obfuscated_c 0); false with _ -> true);

  let src_file = Filename.temp_file "test_strip_obf_" ".c" in
  let bin_file = Filename.temp_file "test_strip_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Stripped code succeeded" (compile_res = 0);

  let run_cmd1 = Printf.sprintf "%s 7" (Filename.quote bin_file) in
  let ic1 = Unix.open_process_in run_cmd1 in
  let out1 = input_line ic1 in
  ignore (Unix.close_process_in ic1);
  assert_bool "Stripped binary compute_clean(7) == 70" (int_of_string (String.trim out1) = 70);

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
