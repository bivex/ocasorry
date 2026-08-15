open Vectis_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 10] Function Merging (Tigress Merge) Tests ---\n%!";

  let c_code = {|
extern int printf(const char *format, ...);
extern int atoi(const char *nptr);

int calculate_area(int w, int h) {
    return w * h;
}

int calculate_perimeter(int w, int h) {
    return (w + h) * 2;
}

int main(int argc, char **argv) {
    int w = atoi(argv[1]);
    int h = atoi(argv[2]);
    int area = calculate_area(w, h);
    int peri = calculate_perimeter(w, h);
    printf("%d %d\n", area, peri);
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
    enable_c_merge = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Merged function __merged_calculate_area_calculate_perimeter generated"
    (try ignore (Str.search_forward (Str.regexp "__merged_calculate_area") obfuscated_c 0); true with _ -> false);

  let src_file = Filename.temp_file "test_merge_obf_" ".c" in
  let bin_file = Filename.temp_file "test_merge_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Merged Functions code succeeded" (compile_res = 0);

  let test_cases = [ (5, 10); (20, 30); (7, 8) ] in
  List.iter
    (fun (w, h) ->
      let expected_area = w * h in
      let expected_peri = (w + h) * 2 in

      let run_cmd = Printf.sprintf "%s %d %d" (Filename.quote bin_file) w h in
      let ic = Unix.open_process_in run_cmd in
      let out_line = input_line ic in
      ignore (Unix.close_process_in ic);

      let parts = String.split_on_char ' ' (String.trim out_line) in
      let actual_area = int_of_string (List.nth parts 0) in
      let actual_peri = int_of_string (List.nth parts 1) in

      assert_bool (Printf.sprintf "Merged Area f(%d, %d) == %d" w h expected_area) (actual_area = expected_area);
      assert_bool (Printf.sprintf "Merged Perimeter f(%d, %d) == %d" w h expected_peri) (actual_peri = expected_peri))
    test_cases;

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
