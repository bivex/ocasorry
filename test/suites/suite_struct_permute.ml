open Vectis_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 19] Struct Field Permutation & Padding Tests ---\n%!";

  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

struct ConfigData {
    int auth_level;
    int user_id;
    int quota;
};

int evaluate_user(int uid, int level, int q) {
    struct ConfigData cfg;
    cfg.auth_level = level;
    cfg.user_id = uid;
    cfg.quota = q;
    return cfg.auth_level + cfg.user_id + cfg.quota;
}

int main(int argc, char **argv) {
    int u = atoi(argv[1]);
    int l = atoi(argv[2]);
    int q = atoi(argv[3]);
    printf("%d\n", evaluate_user(u, l, q));
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
    enable_c_struct_permute = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Padding field __pad_field injected into struct"
    (try ignore (Str.search_forward (Str.regexp "__pad_field") obfuscated_c 0); true with _ -> false);

  let src_file = Filename.temp_file "test_struct_obf_" ".c" in
  let bin_file = Filename.temp_file "test_struct_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Struct Permutation code succeeded" (compile_res = 0);

  let test_cases = [ (1001, 2, 500); (42, 1, 100); (999, 3, 0) ] in
  List.iter
    (fun (u, l, q) ->
      let expected = u + l + q in
      let run_cmd = Printf.sprintf "%s %d %d %d" (Filename.quote bin_file) u l q in
      let ic = Unix.open_process_in run_cmd in
      let out_line = input_line ic in
      ignore (Unix.close_process_in ic);

      let actual = int_of_string (String.trim out_line) in
      assert_bool (Printf.sprintf "Struct Permute evaluate_user(%d, %d, %d) == %d" u l q expected) (actual = expected))
    test_cases;

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
