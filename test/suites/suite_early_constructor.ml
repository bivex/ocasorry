open Ocasorry_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 41] Pre-Main Security Constructor Tests ---\n%!";

  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

int calc_with_stager(int x) {
    return x + 500;
}

int main(int argc, char **argv) {
    int x = atoi(argv[1]);
    printf("%d\n", calc_with_stager(x));
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
    enable_c_early_constructor = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Early constructor attribute __attribute__((constructor(101))) injected"
    (try ignore (Str.search_forward (Str.regexp "constructor") obfuscated_c 0); true with _ -> false);

  let src_file = Filename.temp_file "test_ctor_obf_" ".c" in
  let bin_file = Filename.temp_file "test_ctor_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Pre-Main Constructor code succeeded" (compile_res = 0);

  let run_cmd1 = Printf.sprintf "%s 77" (Filename.quote bin_file) in
  let ic1 = Unix.open_process_in run_cmd1 in
  let out1 = input_line ic1 in
  ignore (Unix.close_process_in ic1);
  assert_bool "Pre-Main Constructor execution calc_with_stager(77) == 577" (int_of_string (String.trim out1) = 577);

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
