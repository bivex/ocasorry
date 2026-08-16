open Vectis_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 66] In-VM Ephemeral AArch64 JIT Escape Gate (Architecture A) Tests ---\n%!";

  let c_code = {|
extern int printf(const char *format, ...);
extern int atoi(const char *nptr);

__attribute__((annotate("vectis:visa")))
int calc_invm_jit_pipeline(int a, int b) {
    int x = (a ^ b);
    int y = (x * 3) + 42;
    int z = (y + 100);
    return z;
}

int main(int argc, char **argv) {
    int a = 12;
    int b = 34;
    int res = calc_invm_jit_pipeline(a, b);
    printf("%d\n", res);
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

  let obf_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "vISA Runtime contains __h_vjit handler"
    (try ignore (Str.search_forward (Str.regexp "__h_vjit:") obf_c 0); true with _ -> false);

  assert_bool "vISA Runtime contains __vectis_vm_alloc_ephemeral_page helper"
    (try ignore (Str.search_forward (Str.regexp "__vectis_vm_alloc_ephemeral_page") obf_c 0); true with _ -> false);

  assert_bool "vISA Runtime contains __vectis_vm_free_ephemeral_page DoD wiper"
    (try ignore (Str.search_forward (Str.regexp "__vectis_vm_free_ephemeral_page") obf_c 0); true with _ -> false);

  let src_file = Filename.temp_file "test_invm_jit_" ".c" in
  let bin_file = Filename.temp_file "test_invm_jit_" ".bin" in
  let oc = open_out src_file in
  output_string oc obf_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  assert_bool "Clang compilation of In-VM JIT Virtualized code succeeded" (Sys.command compile_cmd = 0);

  let ic = Unix.open_process_in (Filename.quote bin_file) in
  let out = input_line ic in
  ignore (Unix.close_process_in ic);

  let actual_val = int_of_string (String.trim out) in
  let expected_val = (((12 lxor 34) * 3) + 42) + 100 in
  assert_bool (Printf.sprintf "In-VM JIT execution result: %d == %d" actual_val expected_val) (actual_val = expected_val);

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
