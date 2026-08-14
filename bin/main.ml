open Ocasorry_lib
open Cli_helpers

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

let () =
  Printf.printf "=================================================================\n";
  Printf.printf "  OcaSorry: Advanced Multi-Target Obfuscator & Compiler Wrapper  \n";
  Printf.printf "=================================================================\n\n%!";

  let x = 100L in
  let y = 200L in
  let expected = Int64.logxor (Int64.add x y) 0x5A5AL in
  Printf.printf "[Input] x0 = %Ld, x1 = %Ld\n" x y;
  Printf.printf "[Expected Output] (x0 + x1) ^ 0x5A5A = %Ld (0x%Lx)\n\n%!" expected expected;

  let full_obf_config : Obfuscation_pipeline.pipeline_config = {
    enable_mba = true;
    enable_opaque = true;
    enable_flattening = true;
  } in

  (* 1. Target: AArch64 (ARM64) Apple Silicon Native JIT *)
  Printf.printf "-----------------------------------------------------------------\n";
  Printf.printf " [Target 1] AArch64 (ARM64) Machine Code JIT Pipeline\n";
  Printf.printf "-----------------------------------------------------------------\n%!";
  (match ArmJIT.obfuscate_and_run_fn2 (build_sample_cfg ()) x y full_obf_config with
  | Ok res ->
      print_hex_dump res.raw_bytes;
      Printf.printf "  Result: %Ld (0x%Lx) -> %s\n\n%!"
        res.result_val res.result_val
        (if res.result_val = expected then "PASSED [OK]" else "FAILED [MISMATCH]")
  | Error err -> Printf.printf "  Error: %s\n\n%!" err);

  (* 2. Target: ECMA-335 CIL Bytecode VM Pipeline *)
  Printf.printf "-----------------------------------------------------------------\n";
  Printf.printf " [Target 2] ECMA-335 CIL Bytecode VM Pipeline\n";
  Printf.printf "-----------------------------------------------------------------\n%!";
  (match CilBytecodeJIT.obfuscate_and_run_fn2 (build_sample_cfg ()) x y full_obf_config with
  | Ok res ->
      print_hex_dump res.raw_bytes;
      Printf.printf "  Result: %Ld (0x%Lx) -> %s\n\n%!"
        res.result_val res.result_val
        (if res.result_val = expected then "PASSED [OK]" else "FAILED [MISMATCH]")
  | Error err -> Printf.printf "  Error: %s\n\n%!" err);

  (* 3. Target: CIL Source-to-Source (Full Tigress Arsenal) *)
  Printf.printf "-----------------------------------------------------------------\n";
  Printf.printf " [Target 3] CIL Source-to-Source Engine (Tigress Techniques)\n";
  Printf.printf "     Passes: EncodeLiterals + VariableSplitting + Signals + MBA + CFF\n";
  Printf.printf "-----------------------------------------------------------------\n%!";
  Printf.printf " Original C Code:\n%s\n" sample_c_program;
  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    enable_c_mba = true;
    enable_c_opaque = true;
    enable_c_flattening = true;
    enable_c_encode_literals = true;
    enable_c_implicit_flow = true;
    enable_c_encode_data = true;
  } in
  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string sample_c_program c_config in
  Printf.printf " Obfuscated C Code:\n\n%s\n%!" obfuscated_c;

  Printf.printf "=================================================================\n";
  Printf.printf "  Multi-Target Execution & Advanced Obfuscation Complete!\n";
  Printf.printf "=================================================================\n%!"
