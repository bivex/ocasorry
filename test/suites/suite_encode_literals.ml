open Ocasorry_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 4] Tigress-Style EncodeLiterals (String Encryption) ---\n%!";

  let c_code = {|
extern int printf(const char *format, ...);

const char* get_secret_message(int flag) {
    if (flag) {
        return "SECRET_FLAG_AUTHENTICATED_OK";
    } else {
        return "ACCESS_DENIED_WRONG_CREDENTIALS";
    }
}

int main(int argc, char **argv) {
    const char *msg = get_secret_message(argc > 1);
    printf("%s\n", msg);
    return 0;
}
|} in

  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    enable_c_mba = false;
    enable_c_opaque = false;
    enable_c_flattening = false;
    enable_c_encode_literals = true;
    enable_c_implicit_flow = false;
    enable_c_encode_data = false;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Plain text string 'SECRET_FLAG_AUTHENTICATED_OK' is hidden"
    (not (String.contains obfuscated_c 'S' && String.contains obfuscated_c 'F' && String.contains obfuscated_c 'L'));

  assert_bool "Encrypted byte arrays (__enc_lit_X) generated"
    (try ignore (Str.search_forward (Str.regexp "__enc_lit") obfuscated_c 0); true with _ -> false);

  let src_file = Filename.temp_file "test_str_obf_" ".c" in
  let bin_file = Filename.temp_file "test_str_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of EncodeLiterals code succeeded" (compile_res = 0);

  let run_cmd1 = Printf.sprintf "%s" (Filename.quote bin_file) in
  let ic1 = Unix.open_process_in run_cmd1 in
  let out1 = input_line ic1 in
  ignore (Unix.close_process_in ic1);
  assert_bool "Decrypted string (branch 1): ACCESS_DENIED_WRONG_CREDENTIALS"
    (String.trim out1 = "ACCESS_DENIED_WRONG_CREDENTIALS");

  let run_cmd2 = Printf.sprintf "%s auth_user" (Filename.quote bin_file) in
  let ic2 = Unix.open_process_in run_cmd2 in
  let out2 = input_line ic2 in
  ignore (Unix.close_process_in ic2);
  assert_bool "Decrypted string (branch 2): SECRET_FLAG_AUTHENTICATED_OK"
    (String.trim out2 = "SECRET_FLAG_AUTHENTICATED_OK");

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
