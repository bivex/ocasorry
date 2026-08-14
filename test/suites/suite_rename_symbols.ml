open Ocasorry_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 33] Identifier Renaming / Symbol Hashing Tests ---\n%!";

  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

static int secret_internal_algorithm(int secret_alpha, int secret_beta) {
    int secret_accumulator = secret_alpha * 2 + secret_beta;
    return secret_accumulator;
}

int main(int argc, char **argv) {
    int a = atoi(argv[1]);
    int b = atoi(argv[2]);
    printf("%d\n", secret_internal_algorithm(a, b));
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
    enable_c_rename_symbols = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Original variable 'secret_accumulator' is renamed"
    (try ignore (Str.search_forward (Str.regexp "secret_accumulator") obfuscated_c 0); false with _ -> true);

  assert_bool "Homoglyph identifier pattern injected"
    (try ignore (Str.search_forward (Str.regexp "_l[0-9a-zA-Z_]+") obfuscated_c 0); true with _ -> false);

  let src_file = Filename.temp_file "test_ren_obf_" ".c" in
  let bin_file = Filename.temp_file "test_ren_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Renamed Symbols code succeeded" (compile_res = 0);

  let test_cases = [ (10, 20, 40); (0, 5, 5); (100, 200, 400) ] in
  List.iter
    (fun (a, b, expected) ->
      let run_cmd = Printf.sprintf "%s %d %d" (Filename.quote bin_file) a b in
      let ic = Unix.open_process_in run_cmd in
      let out_line = input_line ic in
      ignore (Unix.close_process_in ic);

      let actual = int_of_string (String.trim out_line) in
      assert_bool (Printf.sprintf "Renamed Symbols f(%d, %d) == %d" a b expected) (actual = expected))
    test_cases;

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
