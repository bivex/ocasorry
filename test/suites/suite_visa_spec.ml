open Ocasorry_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 61] Python/Sail Dynamic random_vISA Synthesizer Tests ---\n%!";

  let spec_json_path = Filename.temp_file "custom_visa_" ".json" in
  let spec_sail_path = Filename.temp_file "custom_visa_" ".sail" in

  (* 1. Run Python synthesizer to generate random ISA specification and formal Sail file *)
  let gen_cmd = Printf.sprintf "python3 tools/visa_synthesizer.py -o %s -s %s --name=vISA_Custom_Demo_Arch"
    (Filename.quote spec_json_path) (Filename.quote spec_sail_path) in
  let gen_res = Sys.command gen_cmd in
  assert_bool "Python ISA Synthesizer executed successfully" (gen_res = 0);
  assert_bool "Generated JSON ISA spec exists" (Sys.file_exists spec_json_path);
  assert_bool "Generated formal Sail spec exists" (Sys.file_exists spec_sail_path);

  (* 2. Load dynamic specification into OcaSorry engine *)
  let loaded_spec = C_visa_spec_service.VisaSpec.load_from_file spec_json_path in
  assert_bool "Loaded ISA architecture name matches" (loaded_spec.isa_name = "vISA_Custom_Demo_Arch");
  assert_bool "Loaded ISA registers == 16" (loaded_spec.reg_count = 16);

  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

__attribute__((annotate("ocasorry:visa")))
int compute_dynamic_visa(int a, int b) {
    int x = (a + b) * 3;
    int y = (x ^ 0x5A) + 10;
    return y;
}

int main(int argc, char **argv) {
    int a = atoi(argv[1]);
    int b = atoi(argv[2]);
    printf("%d\n", compute_dynamic_visa(a, b));
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

  assert_bool "Bytecode table for compute_dynamic_visa generated"
    (try ignore (Str.search_forward (Str.regexp "__visa_program_compute_dynamic_visa") obfuscated_c 0); true with _ -> false);

  let src_file = Filename.temp_file "test_custom_visa_" ".c" in
  let bin_file = Filename.temp_file "test_custom_visa_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of synthesized dynamic vISA code succeeded" (compile_res = 0);

  let test_cases = [ (5, 10); (0, 0); (20, 30); (100, 200) ] in
  List.iter
    (fun (a, b) ->
      let expected = (((a + b) * 3) lxor 0x5A) + 10 in
      let run_cmd = Printf.sprintf "%s %d %d" (Filename.quote bin_file) a b in
      let ic = Unix.open_process_in run_cmd in
      let out_line = input_line ic in
      ignore (Unix.close_process_in ic);

      let actual = int_of_string (String.trim out_line) in
      assert_bool (Printf.sprintf "Dynamic synthesized vISA compute(%d, %d) == %d (actual: %d)" a b expected actual) (actual = expected))
    test_cases;

  (* Reset to default spec *)
  C_visa_spec_service.VisaSpec.set_active_spec C_visa_spec_service.VisaSpec.default_spec;

  (try Sys.remove spec_json_path with _ -> ());
  (try Sys.remove spec_sail_path with _ -> ());
  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
