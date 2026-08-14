open Ocasorry_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 3] George Necula CIL Source-to-Source (MBA + Opaque + CFF) ---\n%!";

  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

int compute_algorithm(int a, int b) {
    int sum = a + b;
    int diff = a - b;
    int res = (sum ^ diff) + (a & 0xFF);
    return res;
}

int main(int argc, char **argv) {
    int a = atoi(argv[1]);
    int b = atoi(argv[2]);
    int result = compute_algorithm(a, b);
    printf("%d\n", result);
    return 0;
}
|} in

  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    enable_c_mba = true;
    enable_c_opaque = true;
    enable_c_flattening = true;
    enable_c_encode_literals = false;
    enable_c_implicit_flow = false;
    enable_c_encode_data = false;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Obfuscated C contains state dispatcher switch loop"
    (String.contains obfuscated_c 's' && (try ignore (String.index obfuscated_c '_'); true with _ -> false));

  let src_file = Filename.temp_file "test_c_obf_" ".c" in
  let bin_file = Filename.temp_file "test_c_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of CIL-obfuscated C code succeeded" (compile_res = 0);

  let test_pairs = [ (40, 15); (100, 200); (7, 3); (123, 45) ] in
  List.iter
    (fun (a, b) ->
      let sum = a + b in
      let diff = a - b in
      let expected = (sum lxor diff) + (a land 0xFF) in

      let run_cmd = Printf.sprintf "%s %d %d" (Filename.quote bin_file) a b in
      let ic = Unix.open_process_in run_cmd in
      let out_line = input_line ic in
      ignore (Unix.close_process_in ic);

      let actual = int_of_string (String.trim out_line) in
      assert_bool
        (Printf.sprintf "Native C execution compute_algorithm(%d, %d) == %d (actual: %d)" a b expected actual)
        (actual = expected))
    test_pairs;

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
