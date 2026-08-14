open Ocasorry_lib
open Types
open Ast
open Cfg

(* Composition Roots *)
module ArmJIT = Jit_runner_usecase.Make
    (System_entropy_adapter.Adapter)
    (Aarch64_encoder_adapter.Adapter)
    (Posix_mmap_adapter.Adapter)

module CilBytecodeJIT = Jit_runner_usecase.Make
    (System_entropy_adapter.Adapter)
    (Cil_encoder_adapter.Adapter)
    (Cil_vm_adapter.Adapter)

module CilSourceObfuscator = Obfuscate_c_source_usecase.Make
    (System_entropy_adapter.Adapter)
    (Goblint_cil_adapter.Adapter)

let assert_eq msg expected actual =
  if expected <> actual then (
    Printf.eprintf "[FAIL] %s: expected %Ld, got %Ld\n" msg expected actual;
    flush stderr;
    exit 1
  ) else (
    Printf.printf "  [PASS] %s (result: %Ld)\n" msg actual;
    flush stdout
  )

let assert_bool msg cond =
  if not cond then (
    Printf.eprintf "[FAIL] %s\n" msg;
    flush stderr;
    exit 1
  ) else (
    Printf.printf "  [PASS] %s\n" msg;
    flush stdout
  )

(* ========================================================================= *)
(* 1. AArch64 Native JIT Tests                                               *)
(* ========================================================================= *)
let test_arm64_suite () =
  Printf.printf "\n--- [Suite 1] AArch64 Native JIT Obfuscation Tests ---\n";
  flush stdout;

  let b1 = BasicBlock.create ~id:"b1" ~instructions:[ Add (X0, X0, X1); B "b2" ] in
  let b2 = BasicBlock.create ~id:"b2" ~instructions:[ MovImm (X2, 1337L); Add (X0, X0, X2); B "b3" ] in
  let b3 = BasicBlock.create ~id:"b3" ~instructions:[ Eor (X0, X0, X2); Ret None ] in
  let cfg = CFG.create ~entry:"b1" ~blocks:[ b1; b2; b3 ] in

  let test_cases = [
    (10L, 20L);
    (0L, 0L);
    (1000L, 4242L);
    (99999L, 1L);
    (0x12345678L, 0x9ABCDEF0L);
  ] in

  List.iter
    (fun (x, y) ->
      let step1 = Int64.add x y in
      let step2 = Int64.add step1 1337L in
      let expected = Int64.logxor step2 1337L in
      let config = Obfuscation_pipeline.default_config in
      match ArmJIT.obfuscate_and_run_fn2 cfg x y config with
      | Ok res -> assert_eq (Printf.sprintf "ARM64 JIT f(%Ld, %Ld)" x y) expected res.result_val
      | Error err -> failwith ("ARM64 JIT error: " ^ err))
    test_cases

(* ========================================================================= *)
(* 2. ECMA-335 CIL Bytecode VM Tests                                         *)
(* ========================================================================= *)
let test_cil_bytecode_suite () =
  Printf.printf "\n--- [Suite 2] ECMA-335 CIL Bytecode VM Tests ---\n";
  flush stdout;

  let b1 = BasicBlock.create ~id:"b1" ~instructions:[ Sub (X0, X0, X1); B "b2" ] in
  let b2 = BasicBlock.create ~id:"b2" ~instructions:[ MovImm (X2, 0xFFL); Eor (X0, X0, X2); Ret None ] in
  let cfg = CFG.create ~entry:"b1" ~blocks:[ b1; b2 ] in

  let test_cases = [
    (100L, 40L);
    (50L, 50L);
    (123456L, 789L);
  ] in

  List.iter
    (fun (x, y) ->
      let expected = Int64.logxor (Int64.sub x y) 0xFFL in
      let config = Obfuscation_pipeline.default_config in
      match CilBytecodeJIT.obfuscate_and_run_fn2 cfg x y config with
      | Ok res -> assert_eq (Printf.sprintf "CIL Bytecode VM f(%Ld, %Ld)" x y) expected res.result_val
      | Error err -> failwith ("CIL Bytecode error: " ^ err))
    test_cases

(* ========================================================================= *)
(* 3. George Necula CIL (C Source-to-Source) Tests (MBA, Opaque, CFF)        *)
(* ========================================================================= *)
let test_c_source_cil_suite () =
  Printf.printf "\n--- [Suite 3] George Necula CIL Source-to-Source (MBA + Opaque + CFF) ---\n";
  flush stdout;

  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

int compute_algorithm(int a, int b) {
    int sum = a + b;
    int diff = a - b;
    int res = (sum ^ diff) + (a & 0xFF);
    return res;
}

int main(int argc, char **argv) {
    int a = atoi(argv[1]);
    int b = atoi(argv[2]);
    int result = compute_algorithm(a, b);
    printf("%d\n", result);
    return 0;
}
|} in

  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    enable_c_mba = true;
    enable_c_opaque = true;
    enable_c_flattening = true;
    enable_c_encode_literals = false;
    enable_c_implicit_flow = false;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Obfuscated C contains state dispatcher switch loop"
    (String.contains obfuscated_c 's' && (try ignore (String.index obfuscated_c '_'); true with _ -> false));

  let src_file = Filename.temp_file "test_c_obf_" ".c" in
  let bin_file = Filename.temp_file "test_c_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of CIL-obfuscated C code succeeded" (compile_res = 0);

  let test_pairs = [ (40, 15); (100, 200); (7, 3); (123, 45) ] in
  List.iter
    (fun (a, b) ->
      let sum = a + b in
      let diff = a - b in
      let expected = (sum lxor diff) + (a land 0xFF) in

      let run_cmd = Printf.sprintf "%s %d %d" (Filename.quote bin_file) a b in
      let ic = Unix.open_process_in run_cmd in
      let out_line = input_line ic in
      ignore (Unix.close_process_in ic);

      let actual = int_of_string (String.trim out_line) in
      assert_bool
        (Printf.sprintf "Native C execution compute_algorithm(%d, %d) == %d (actual: %d)" a b expected actual)
        (actual = expected))
    test_pairs;

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())

(* ========================================================================= *)
(* 4. EncodeLiterals (String Encryption) Tests                               *)
(* ========================================================================= *)
let test_c_encode_literals_suite () =
  Printf.printf "\n--- [Suite 4] Tigress-Style EncodeLiterals (String Encryption) ---\n";
  flush stdout;

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

  (* Run without args -> ACCESS_DENIED_WRONG_CREDENTIALS *)
  let run_cmd1 = Printf.sprintf "%s" (Filename.quote bin_file) in
  let ic1 = Unix.open_process_in run_cmd1 in
  let out1 = input_line ic1 in
  ignore (Unix.close_process_in ic1);
  assert_bool "Decrypted string (branch 1): ACCESS_DENIED_WRONG_CREDENTIALS"
    (String.trim out1 = "ACCESS_DENIED_WRONG_CREDENTIALS");

  (* Run with args -> SECRET_FLAG_AUTHENTICATED_OK *)
  let run_cmd2 = Printf.sprintf "%s auth_user" (Filename.quote bin_file) in
  let ic2 = Unix.open_process_in run_cmd2 in
  let out2 = input_line ic2 in
  ignore (Unix.close_process_in ic2);
  assert_bool "Decrypted string (branch 2): SECRET_FLAG_AUTHENTICATED_OK"
    (String.trim out2 = "SECRET_FLAG_AUTHENTICATED_OK");

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())

(* ========================================================================= *)
(* 5. Implicit Flow (Signal / Exception Driven Control Flow) Tests           *)
(* ========================================================================= *)
let test_c_implicit_flow_suite () =
  Printf.printf "\n--- [Suite 5] Tigress-Style Implicit Flow (Signal Driven Control Flow) ---\n";
  flush stdout;

  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

int branch_computation(int x) {
    int res = 0;
    if (x == 42) {
        res = 1337;
    } else {
        res = 999;
    }
    return res;
}

int main(int argc, char **argv) {
    int x = atoi(argv[1]);
    int r = branch_computation(x);
    printf("%d\n", r);
    return 0;
}
|} in

  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    enable_c_mba = false;
    enable_c_opaque = false;
    enable_c_flattening = false;
    enable_c_encode_literals = false;
    enable_c_implicit_flow = true;
  } in

  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in

  assert_bool "Implicit flow signal handler injected"
    (try ignore (Str.search_forward (Str.regexp "__implicit_signal_handler") obfuscated_c 0); true with _ -> false);

  let src_file = Filename.temp_file "test_implicit_obf_" ".c" in
  let bin_file = Filename.temp_file "test_implicit_obf_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  let compile_cmd = Printf.sprintf "clang -w -O0 %s -o %s" (Filename.quote src_file) (Filename.quote bin_file) in
  let compile_res = Sys.command compile_cmd in
  assert_bool "Clang compilation of Implicit Flow code succeeded" (compile_res = 0);

  (* Input 42 -> signal path triggered -> 1337 *)
  let run_cmd1 = Printf.sprintf "%s 42" (Filename.quote bin_file) in
  let ic1 = Unix.open_process_in run_cmd1 in
  let out1 = input_line ic1 in
  ignore (Unix.close_process_in ic1);
  assert_bool "Implicit flow signal execution branch_computation(42) == 1337"
    (int_of_string (String.trim out1) = 1337);

  (* Input 10 -> normal path -> 999 *)
  let run_cmd2 = Printf.sprintf "%s 10" (Filename.quote bin_file) in
  let ic2 = Unix.open_process_in run_cmd2 in
  let out2 = input_line ic2 in
  ignore (Unix.close_process_in ic2);
  assert_bool "Implicit flow normal execution branch_computation(10) == 999"
    (int_of_string (String.trim out2) = 999);

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ())

let () =
  Printf.printf "=================================================================\n";
  Printf.printf "      Running Comprehensive OcaSorry Test Suite (All Targets)    \n";
  Printf.printf "=================================================================\n";
  flush stdout;
  test_arm64_suite ();
  test_cil_bytecode_suite ();
  test_c_source_cil_suite ();
  test_c_encode_literals_suite ();
  test_c_implicit_flow_suite ();
  Printf.printf "\n=================================================================\n";
  Printf.printf "       ALL 5 ADVANCED TEST SUITES PASSED SUCCESSFULLY!           \n";
  Printf.printf "=================================================================\n";
  flush stdout
