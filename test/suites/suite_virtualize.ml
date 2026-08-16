open Vectis_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 22] random_vISA VCPU Bytecode Virtualization Tests ---\n%!";

  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

int virtual_vector_compute(int a, int b) {
    int res = ((a + b) * 3) ^ 0x5A;
    return res;
}

int main(int argc, char **argv) {
    int a = atoi(argv[1]);
    int b = atoi(argv[2]);
    printf("%d\n", virtual_vector_compute(a, b));
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
    enable_c_virtualize = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Vector Bytecode __visa_program generated in static memory"
    (try ignore (Str.search_forward (Str.regexp "__visa_program") obfuscated_c 0); true with _ -> false);

  let src_file = Filename.temp_file "test_visa_obf_" ".c" in
  let bin_file = Filename.temp_file "test_visa_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;
  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s 2>&1" (Filename.quote src_file) (Filename.quote bin_file) in


  let ic = Unix.open_process_in compile_cmd in
  let err_lines = ref [] in
  (try while true do err_lines := input_line ic :: !err_lines done with End_of_file -> ());
  let status = Unix.close_process_in ic in
  if status <> Unix.WEXITED 0 then (
    Printf.eprintf "[FAIL] Clang error output:\n%s\n%!" (String.concat "\n" (List.rev !err_lines));
    assert_bool "Clang compilation of random_vISA Virtualized code succeeded" false
  );

  let test_cases = [ (10, 20); (0, 0); (5, 15); (100, 200) ] in
  List.iter
    (fun (a, b) ->
      let expected = ((a + b) * 3) lxor 0x5A in
      let run_cmd = Printf.sprintf "%s %d %d" (Filename.quote bin_file) a b in
      let ic = Unix.open_process_in run_cmd in
      let out_line = input_line ic in
      ignore (Unix.close_process_in ic);

      let actual = int_of_string (String.trim out_line) in
      assert_bool (Printf.sprintf "random_vISA VCPU virtual_vector_compute(%d, %d) == %d" a b expected) (actual = expected))
    test_cases;

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
