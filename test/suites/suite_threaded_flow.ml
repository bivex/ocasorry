open Vectis_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 28] Multi-Threaded Implicit Flow Tests ---\n%!";

  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

int calc_threaded_branch(int x) {
    int res = 0;
    if (x > 50) {
        res = x * 2;
    } else {
        res = x + 100;
    }
    return res;
}

int main(int argc, char **argv) {
    int x = atoi(argv[1]);
    printf("%d\n", calc_threaded_branch(x));
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
    enable_c_threaded_flow = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  let src_file = Filename.temp_file "test_th_obf_" ".c" in
  let bin_file = Filename.temp_file "test_th_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 -lpthread %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Multi-Threaded Flow code succeeded" (compile_res = 0);

  let test_cases = [ (100, 200); (10, 110); (51, 102); (0, 100) ] in
  List.iter
    (fun (x, expected) ->
      let run_cmd = Printf.sprintf "%s %d" (Filename.quote bin_file) x in
      let ic = Unix.open_process_in run_cmd in
      let out_line = input_line ic in
      ignore (Unix.close_process_in ic);

      let actual = int_of_string (String.trim out_line) in
      assert_bool (Printf.sprintf "Threaded Flow calc_threaded_branch(%d) == %d" x expected) (actual = expected))
    test_cases;

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
