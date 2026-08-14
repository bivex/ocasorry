open Ocasorry_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 20] Pointer Swizzling & Masking Tests ---\n%!";

  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

int dereference_computation(int val) {
    int secret = val + 100;
    int *ptr = &secret;
    int read_back = *ptr;
    return read_back * 2;
}

int main(int argc, char **argv) {
    int v = atoi(argv[1]);
    printf("%d\n", dereference_computation(v));
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
    enable_c_pointer_mask = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  let src_file = Filename.temp_file "test_ptr_obf_" ".c" in
  let bin_file = Filename.temp_file "test_ptr_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Pointer Masking code succeeded" (compile_res = 0);

  let test_cases = [ 5; 42; 0; -10 ] in
  List.iter
    (fun v ->
      let expected = (v + 100) * 2 in
      let run_cmd = Printf.sprintf "%s %d" (Filename.quote bin_file) v in
      let ic = Unix.open_process_in run_cmd in
      let out_line = input_line ic in
      ignore (Unix.close_process_in ic);

      let actual = int_of_string (String.trim out_line) in
      assert_bool (Printf.sprintf "Pointer Masking dereference_computation(%d) == %d" v expected) (actual = expected))
    test_cases;

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
