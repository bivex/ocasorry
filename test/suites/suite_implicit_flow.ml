open Ocasorry_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 5] Tigress-Style Implicit Flow (Signal Driven Control Flow) ---\n%!";

  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

int branch_computation(int x) {
    int res = 0;
    if (x == 42) {
        res = 1337;
    } else {
        res = 999;
    }
    return res;
}

int main(int argc, char **argv) {
    int x = atoi(argv[1]);
    int r = branch_computation(x);
    printf("%d\n", r);
    return 0;
}
|} in

  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    enable_c_mba = false;
    enable_c_polynomial_mba = false;
    enable_c_opaque = false;
    enable_c_flattening = false;
    enable_c_encode_literals = false;
    enable_c_implicit_flow = true;
    enable_c_encode_data = false;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Implicit flow signal handler injected"
    (try ignore (Str.search_forward (Str.regexp "__implicit_signal_handler") obfuscated_c 0); true with _ -> false);

  let src_file = Filename.temp_file "test_implicit_obf_" ".c" in
  let bin_file = Filename.temp_file "test_implicit_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Implicit Flow code succeeded" (compile_res = 0);

  let run_cmd1 = Printf.sprintf "%s 42" (Filename.quote bin_file) in
  let ic1 = Unix.open_process_in run_cmd1 in
  let out1 = input_line ic1 in
  ignore (Unix.close_process_in ic1);
  assert_bool "Implicit flow signal execution branch_computation(42) == 1337"
    (int_of_string (String.trim out1) = 1337);

  let run_cmd2 = Printf.sprintf "%s 10" (Filename.quote bin_file) in
  let ic2 = Unix.open_process_in run_cmd2 in
  let out2 = input_line ic2 in
  ignore (Unix.close_process_in ic2);
  assert_bool "Implicit flow normal execution branch_computation(10) == 999"
    (int_of_string (String.trim out2) = 999);

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
