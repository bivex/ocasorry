open Vectis_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 63] Non-Default vISA Layout & Control-Flow Branching Tests ---\n%!";

  (* 1. Construct a non-default custom layout *)
  (* Standard default layout is: vd_shift=7, funct3_shift=12, vs1_shift=15, vs2_shift=20, vm_shift=25 *)
  (* Custom non-default arrangement: pair (vd+funct3)=17..24, vm=25, vs2=7..11, vs1=12..16 *)
  let custom_layout : C_visa_spec.visa_field_layout = {
    funct6_shift = 26;
    funct6_mask  = 0x3F;
    vm_shift     = 25;
    vd_shift     = 17;
    funct3_shift = 22;
    vs1_shift    = 12;
    vs2_shift    = 7;
    opcode_val   = 0x2B;
  } in

  C_visa_spec.validate_layout custom_layout;

  let custom_spec : C_visa_spec.visa_spec = {
    C_visa_spec.default_spec with
    isa_name = "vISA_Custom_Layout_17";
    layout   = custom_layout;
  } in

  C_visa_spec_service.VisaSpec.set_active_spec custom_spec;

  (* 2. C source with branches (if/else) and loops to test branch/jump encoding with vd_shift=17 *)
  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

__attribute__((annotate("vectis:visa")))
int compute_branched_loop(int x, int limit) {
    int acc = 0;
    if (x >= limit) {
        acc = x * 2;
    } else {
        acc = limit - x;
    }
    for (int i = 0; i < 5; i++) {
        if (acc >= 10) {
            acc = acc + 1;
        } else {
            acc = acc + 3;
        }
    }
    return acc;
}

int main(int argc, char **argv) {
    int x = atoi(argv[1]);
    int lim = atoi(argv[2]);
    printf("%d\n", compute_branched_loop(x, lim));
    return 0;
}
|} in

  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    Obfuscate_c_source_usecase.default_c_config with
    enable_c_virtualize = true;
    enable_c_mba = false;
    enable_c_opaque = false;
    enable_c_flattening = false;
    enable_c_encode_literals = false;
    enable_c_encode_data = false;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  let src_file = Filename.temp_file "test_layout_visa_" ".c" in
  let bin_file = Filename.temp_file "test_layout_visa_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of non-default layout branched vISA code succeeded" (compile_res = 0);

  (* 3. Test vectors across branch conditions *)
  let reference_compute x limit =
    let acc = ref (if x >= limit then x * 2 else limit - x) in
    for _ = 0 to 4 do
      if !acc >= 10 then acc := !acc + 1
      else acc := !acc + 3
    done;
    !acc
  in

  let test_cases = [ (10, 5); (3, 8); (0, 0); (15, 15); (-5, 10); (50, 20) ] in
  List.iter
    (fun (x, lim) ->
      let expected = reference_compute x lim in
      let run_cmd = Printf.sprintf "%s %d %d" (Filename.quote bin_file) x lim in
      let ic = Unix.open_process_in run_cmd in
      let out_line = input_line ic in
      ignore (Unix.close_process_in ic);
      let actual = int_of_string (String.trim out_line) in
      assert_bool (Printf.sprintf "Custom layout compute(%d, %d) == %d (actual: %d)" x lim expected actual) (actual = expected))
    test_cases;

  (* Reset to default spec *)
  C_visa_spec_service.VisaSpec.set_active_spec C_visa_spec_service.VisaSpec.default_spec;

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
