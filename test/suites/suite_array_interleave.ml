open Ocasorry_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 18] Array Folding & Interleaving Tests ---\n%!";

  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

int sum_array_elements(int idx) {
    int arr[5] = { 10, 20, 30, 40, 50 };
    if (idx < 0 || idx >= 5) return -1;
    return arr[idx];
}

int main(int argc, char **argv) {
    int idx = atoi(argv[1]);
    printf("%d\n", sum_array_elements(idx));
    return 0;
}
|} in

  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    enable_c_mba = false;
    enable_c_polynomial_mba = false;
    enable_c_opaque = false;
    enable_c_dynamic_opaque = false;
    enable_c_bogus_cf = false;
    enable_c_loop_unroll = false;
    enable_c_loop_fission = false;
    enable_c_indirect_jump = false;
    enable_c_flattening = false;
    enable_c_encode_literals = false;
    enable_c_implicit_flow = false;
    enable_c_encode_data = false;
    enable_c_merge = false;
    enable_c_outline = false;
    enable_c_lut = false;
    enable_c_array_interleave = true;
    enable_c_struct_permute = false;
    enable_c_pointer_mask = false;
    enable_c_homomorphic = false;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  let src_file = Filename.temp_file "test_arr_obf_" ".c" in
  let bin_file = Filename.temp_file "test_arr_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Array Interleaving code succeeded" (compile_res = 0);

  let test_cases = [ (0, 10); (1, 20); (2, 30); (3, 40); (4, 50) ] in
  List.iter
    (fun (idx, expected) ->
      let run_cmd = Printf.sprintf "%s %d" (Filename.quote bin_file) idx in
      let ic = Unix.open_process_in run_cmd in
      let out_line = input_line ic in
      ignore (Unix.close_process_in ic);

      let actual = int_of_string (String.trim out_line) in
      assert_bool (Printf.sprintf "Array Interleave arr[%d] == %d" idx expected) (actual = expected))
    test_cases;

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
