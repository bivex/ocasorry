open Vectis_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 31] Call Graph Flattening (Indirect Calls) Tests ---\n%!";

  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

int step_alpha(int x) {
    return x * 3;
}

int step_beta(int x) {
    return x + 50;
}

int execute_chain(int x) {
    int v = step_alpha(x);
    return step_beta(v);
}

int main(int argc, char **argv) {
    int x = atoi(argv[1]);
    printf("%d\n", execute_chain(x));
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
    enable_c_call_flatten = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Global dispatch table __indirect_call_table generated"
    (try ignore (Str.search_forward (Str.regexp "__indirect_call_table") obfuscated_c 0); true with _ -> false);

  let src_file = Filename.temp_file "test_cflat_obf_" ".c" in
  let bin_file = Filename.temp_file "test_cflat_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Call Graph Flattened code succeeded" (compile_res = 0);

  let test_cases = [ (10, 80); (0, 50); (5, 65); (100, 350) ] in
  List.iter
    (fun (x, expected) ->
      let run_cmd = Printf.sprintf "%s %d" (Filename.quote bin_file) x in
      let ic = Unix.open_process_in run_cmd in
      let out_line = input_line ic in
      ignore (Unix.close_process_in ic);

      let actual = int_of_string (String.trim out_line) in
      assert_bool (Printf.sprintf "Call Graph Flatten execute_chain(%d) == %d" x expected) (actual = expected))
    test_cases;

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
