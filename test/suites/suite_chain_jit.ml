open Vectis_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 65] Multiple Chained Ephemeral JIT & Pipeline Tests ---\n%!";

  (* Test 1: 4-Stage Ephemeral JIT Mathematical Pipeline *)
  let c_pipeline_code = {|
extern int printf(const char *format, ...);

__attribute__((annotate("vectis:ephemeral")))
int pipe_stage1_hash(int x) {
    int a = (x ^ 0x5A5A);
    int b = (a * 3) + 7;
    return b;
}

__attribute__((annotate("vectis:ephemeral")))
int pipe_stage2_branch(int x) {
    if (x > 50000) {
        return (x ^ 0x1234) + 100;
    } else {
        return (x ^ 0x4321) - 100;
    }
}

__attribute__((annotate("vectis:ephemeral")))
int pipe_stage3_affine(int x) {
    int m = (x * 5) + 42;
    return (m ^ 0xCAFE);
}

__attribute__((annotate("vectis:ephemeral")))
int pipe_stage4_finalize(int x) {
    if (x >= 0) {
        return (x ^ 0x7777);
    } else {
        return ((-x) ^ 0x8888);
    }
}

int main(int argc, char **argv) {
    int input = 123;
    int s1 = pipe_stage1_hash(input);
    int s2 = pipe_stage2_branch(s1);
    int s3 = pipe_stage3_affine(s2);
    int s4 = pipe_stage4_finalize(s3);

    printf("%d %d %d %d\n", s1, s2, s3, s4);
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
    enable_c_ephemeral_payload = true;
  } in

  let obf_pipeline = CilSourceObfuscator.obfuscate_c_string c_pipeline_code c_config in

  let src_file1 = Filename.temp_file "test_chain_jit_" ".c" in
  let bin_file1 = Filename.temp_file "test_chain_jit_" ".bin" in
  let oc1 = open_out src_file1 in
  output_string oc1 obf_pipeline;
  close_out oc1;

  let compile_cmd1 = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file1) (Filename.quote bin_file1) in
  assert_bool "Clang compilation of 4-Stage JIT Pipeline succeeded" (Sys.command compile_cmd1 = 0);

  let ic1 = Unix.open_process_in (Filename.quote bin_file1) in
  let out1 = input_line ic1 in
  ignore (Unix.close_process_in ic1);

  let parts1 = String.split_on_char ' ' (String.trim out1) in
  let s1 = int_of_string (List.nth parts1 0) in
  let s2 = int_of_string (List.nth parts1 1) in
  let s3 = int_of_string (List.nth parts1 2) in
  let s4 = int_of_string (List.nth parts1 3) in

  let exp_s1 = ((123 lxor 0x5A5A) * 3) + 7 in
  let exp_s2 = if exp_s1 > 50000 then (exp_s1 lxor 0x1234) + 100 else (exp_s1 lxor 0x4321) - 100 in
  let exp_s3 = ((exp_s2 * 5) + 42) lxor 0xCAFE in
  let exp_s4 = if exp_s3 >= 0 then exp_s3 lxor 0x7777 else (-exp_s3) lxor 0x8888 in

  assert_bool (Printf.sprintf "Pipeline Stage 1: %d == %d" s1 exp_s1) (s1 = exp_s1);
  assert_bool (Printf.sprintf "Pipeline Stage 2: %d == %d" s2 exp_s2) (s2 = exp_s2);
  assert_bool (Printf.sprintf "Pipeline Stage 3: %d == %d" s3 exp_s3) (s3 = exp_s3);
  assert_bool (Printf.sprintf "Pipeline Stage 4: %d == %d" s4 exp_s4) (s4 = exp_s4);

  (try Sys.remove src_file1 with _ -> ());
  (try Sys.remove bin_file1 with _ -> ());

  (* Test 2: High-Frequency Repeated Invocations in a Loop (5,000 calls) *)
  let c_loop_code = {|
extern int printf(const char *format, ...);

__attribute__((annotate("vectis:ephemeral")))
int loop_step_jit(int x) {
    return ((x ^ 0x42) * 3) + 1;
}

int main(int argc, char **argv) {
    int val = 7;
    for (int i = 0; i < 5000; i++) {
        val = loop_step_jit(val);
    }
    printf("%d\n", val);
    return 0;
}
|} in

  let obf_loop = CilSourceObfuscator.obfuscate_c_string c_loop_code c_config in
  let src_file2 = Filename.temp_file "test_loop_jit_" ".c" in
  let bin_file2 = Filename.temp_file "test_loop_jit_" ".bin" in
  let oc2 = open_out src_file2 in
  output_string oc2 obf_loop;
  close_out oc2;

  let compile_cmd2 = Printf.sprintf "clang -w -O2 %s -o %s" (Filename.quote src_file2) (Filename.quote bin_file2) in
  assert_bool "Clang compilation of 5,000 Loop JIT succeeded" (Sys.command compile_cmd2 = 0);

  let ic2 = Unix.open_process_in (Filename.quote bin_file2) in
  let out2 = input_line ic2 in
  ignore (Unix.close_process_in ic2);

  let loop_res = int_of_string (String.trim out2) in
  let rec sim_loop v n =
    if n = 0 then v
    else
      let next_v = ((v lxor 0x42) * 3) + 1 in
      sim_loop (Int32.to_int (Int32.of_int next_v)) (n - 1)
  in
  let exp_loop = sim_loop 7 5000 in
  assert_bool (Printf.sprintf "5,000 Loop JIT executions: %d == %d" loop_res exp_loop) (loop_res = exp_loop);

  (try Sys.remove src_file2 with _ -> ());
  (try Sys.remove bin_file2 with _ -> ())
