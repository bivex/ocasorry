open Vectis_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 12] Dynamic / Math-Property Opaque Predicates Tests ---\n%!";

  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

int calc_property(int x) {
    int res = (x * 7) + 13;
    return res;
}

int main(int argc, char **argv) {
    int x = atoi(argv[1]);
    printf("%d\n", calc_property(x));
    return 0;
}
|} in

  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    Obfuscate_c_source_usecase.default_c_config with
    enable_c_mba = false;
    enable_c_opaque = false;
    enable_c_dynamic_opaque = true;
    enable_c_flattening = false;
    enable_c_encode_literals = false;
    enable_c_encode_data = false;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  let src_file = Filename.temp_file "test_dyn_op_" ".c" in
  let bin_file = Filename.temp_file "test_dyn_op_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Dynamic Opaque Predicates code succeeded" (compile_res = 0);

  let test_cases = [ 0; 1; 10; 42; -5; 1000 ] in
  List.iter
    (fun x ->
      let expected = (x * 7) + 13 in
      let run_cmd = Printf.sprintf "%s %d" (Filename.quote bin_file) x in
      let ic = Unix.open_process_in run_cmd in
      let out_line = input_line ic in
      ignore (Unix.close_process_in ic);

      let actual = int_of_string (String.trim out_line) in
      assert_bool (Printf.sprintf "Dynamic Opaque calc_property(%d) == %d" x expected) (actual = expected))
    test_cases;

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
