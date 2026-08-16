open Vectis_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 49] Stack Memory Aliasing (S-Box) Tests ---\n%!";

  (* Stack aliasing pass is currently a semantics-preserving no-op —
     the previous implementation replaced function bodies with a hardcoded
     skeleton, breaking program correctness. The pass now safely skips
     transformation until a proper slot-substitution implementation is added.
     Tests here verify: (a) the pass doesn't crash, (b) semantics are preserved. *)

  let c_code = {|
int calc_stack_aliased(int x) {
    return x + 10;
}

int main(int argc, char **argv) {
    return calc_stack_aliased(20);
}
|} in

  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    Obfuscate_c_source_usecase.default_c_config with
    enable_c_mba = false;
    enable_c_opaque = false;
    enable_c_flattening = false;
    enable_c_encode_literals = false;
    enable_c_encode_data = false;
    enable_c_stack_aliasing = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  (* Pass is no-op: semantics-preserving, function body is not replaced *)
  assert_bool "Stack aliasing pass produces valid C output (non-empty)"
    (String.length obfuscated_c > 0);

  let src_file = Filename.temp_file "test_stackalias_obf_" ".c" in
  let bin_file = Filename.temp_file "test_stackalias_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Stack Memory Aliased code succeeded" (compile_res = 0);

  (* Semantics preserved: x + 10 with x=20 => 30 *)
  let run_cmd1 = Printf.sprintf "%s" (Filename.quote bin_file) in
  let ret1 = Sys.command run_cmd1 in
  assert_bool "Stack aliasing preserves semantics: calc_stack_aliased(20) == 30" (ret1 = 30);

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())
