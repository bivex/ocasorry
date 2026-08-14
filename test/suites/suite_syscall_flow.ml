open Ocasorry_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 29] Syscall Error Return Flow Tests ---\n%!";

  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

int calc_syscall_branch(int x) {
    int res = 0;
    if (x == 1337) {
        res = 777;
    } else {
        res = 333;
    }
    return res;
}

int main(int argc, char **argv) {
    int x = atoi(argv[1]);
    printf("%d\n", calc_syscall_branch(x));
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
    enable_c_syscall_flow = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  let src_file = Filename.temp_file "test_sys_obf_" ".c" in
  let bin_file = Filename.temp_file "test_sys_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Syscall Flow code succeeded" (compile_res = 0);

  let run_cmd1 = Printf.sprintf "%s 1337" (Filename.quote bin_file) in
  let ic1 = Unix.open_process_in run_cmd1 in
  let out1 = input_line ic1 in
  ignore (Unix.close_process_in ic1);
  assert_bool "Syscall Flow failed path calc_syscall_branch(1337) == 777" (int_of_string (String.trim out1) = 777);

  let run_cmd2 = Printf.sprintf "%s 42" (Filename.quote bin_file) in
  let ic2 = Unix.open_process_in run_cmd2 in
  let out2 = input_line ic2 in
  ignore (Unix.close_process_in ic2);
  assert_bool "Syscall Flow normal path calc_syscall_branch(42) == 333" (int_of_string (String.trim out2) = 333);

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
