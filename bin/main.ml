open Ocasorry_lib
open Cli_helpers

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

module TwoTierJIT = Two_tier_jit_usecase.Make
    (System_entropy_adapter.Adapter)
    (Aarch64_encoder_adapter.Adapter)

let run_demo () =
  Printf.printf "=================================================================\n";
  Printf.printf "  OcaSorry: Multi-Target Obfuscator & Multi-Tier JIT Engine     \n";
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

  (* 3. Target: CIL Source-to-Source (Full Tigress Arsenal + High-Order PolyMBA + BCF) *)
  Printf.printf "-----------------------------------------------------------------\n";
  Printf.printf " [Target 3] CIL Source-to-Source Engine (Tigress Techniques)\n";
  Printf.printf "     Passes: EncodeLiterals + VariableSplitting + Signals + PolyMBA + CFF + BCF\n";
  Printf.printf "-----------------------------------------------------------------\n%!";
  Printf.printf " Original C Code:\n%s\n" sample_c_program;
  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    Obfuscate_c_source_usecase.default_c_config with
    enable_c_mba = false;
    enable_c_polynomial_mba = true;
    enable_c_opaque = true;
    enable_c_dynamic_opaque = true;
    enable_c_bogus_cf = true;
    enable_c_flattening = true;
    enable_c_encode_literals = true;
    enable_c_implicit_flow = true;
    enable_c_encode_data = true;
  } in
  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string sample_c_program c_config in
  Printf.printf " Obfuscated C Code:\n\n%s\n%!" obfuscated_c;

  (* 4. Target: Two-Level JITting + Signal-Driven Implicit Flow (Hardware Fault Redirection) *)
  Printf.printf "-----------------------------------------------------------------\n";
  Printf.printf " [Target 4] Two-Level JITting + Hardware-Level Implicit Flow\n";
  Printf.printf "     Tier 1: Outer JIT Hardware Trap Stager (BRK/SIGTRAP)\n";
  Printf.printf "     Tier 2: Inner Encrypted Payload (Decrypted & Executed on Fault)\n";
  Printf.printf "-----------------------------------------------------------------\n%!";
  (match TwoTierJIT.execute_two_tier_fn2 (build_sample_cfg ()) x y full_obf_config with
  | Ok res ->
      Printf.printf "  [Tier 1 Binary Stager] Size: %d bytes\n" (Bytes.length res.tier1_bytes);
      print_hex_dump res.tier1_bytes;
      Printf.printf "  [Tier 2 Encrypted Payload] Key: 0x%02X, Size: %d bytes\n"
        res.encryption_key (Bytes.length res.tier2_encrypted_bytes);
      print_hex_dump res.tier2_encrypted_bytes;
      Printf.printf "  Result: %Ld (0x%Lx) -> %s\n\n%!"
        res.result_val res.result_val
        (if res.result_val = expected then "PASSED [OK]" else "FAILED [MISMATCH]")
  | Error err -> Printf.printf "  Error: %s\n\n%!" err);

  Printf.printf "=================================================================\n";
  Printf.printf "  All 4 Multi-Target & Multi-Tier Execution Pipelines Complete!  \n";
  Printf.printf "=================================================================\n%!"

let () =
  let in_file = ref "" in
  let out_file = ref "" in
  let enable_mba = ref false in
  let enable_poly_mba = ref true in
  let enable_cff = ref true in
  let enable_opaque = ref true in
  let enable_dyn_opaque = ref false in
  let enable_bcf = ref false in
  let enable_unroll = ref false in
  let enable_fission = ref false in
  let enable_indirect = ref false in
  let enable_literals = ref true in
  let enable_split = ref true in
  let enable_implicit = ref false in
  let enable_sigfpe = ref false in
  let enable_sigill = ref false in
  let enable_threaded = ref false in
  let enable_syscall = ref false in
  let enable_merge = ref false in
  let enable_outline = ref false in
  let enable_inline = ref false in
  let enable_call_flatten = ref false in
  let enable_bogus_calls = ref false in
  let enable_rename = ref false in
  let enable_strip = ref false in
  let enable_anti_debug = ref false in
  let enable_anti_disasm = ref false in
  let enable_self_checksum = ref false in
  let enable_timing_check = ref false in
  let enable_hook_detect = ref false in
  let enable_lut = ref false in
  let enable_interleave = ref false in
  let enable_permute_struct = ref false in
  let enable_pointer_mask = ref false in
  let enable_homomorphic = ref false in
  let enable_virtualize = ref false in
  let enable_nested_vm = ref false in
  let enable_self_mod_vm = ref false in
  let enable_jitify = ref false in

  let speclist = [
    ("-i", Arg.Set_string in_file, "Input C source file to obfuscate");
    ("-o", Arg.Set_string out_file, "Output obfuscated C file path");
    ("--mba", Arg.Set enable_mba, "Enable Linear Mixed Boolean-Arithmetic");
    ("--poly-mba", Arg.Set enable_poly_mba, "Enable High-Order Polynomial MBA (Anti-Z3)");
    ("--no-poly-mba", Arg.Clear enable_poly_mba, "Disable High-Order Polynomial MBA");
    ("--cff", Arg.Set enable_cff, "Enable Control Flow Flattening");
    ("--no-cff", Arg.Clear enable_cff, "Disable Control Flow Flattening");
    ("--opaque", Arg.Set enable_opaque, "Enable Invariant Opaque Predicates");
    ("--dyn-opaque", Arg.Set enable_dyn_opaque, "Enable Dynamic / Math-Property Opaque Predicates");
    ("--bcf", Arg.Set enable_bcf, "Enable Bogus Control Flow (Code Cloning & Mutation)");
    ("--unroll", Arg.Set enable_unroll, "Enable Loop Unrolling & Jittering");
    ("--fission", Arg.Set enable_fission, "Enable Loop Fission / Segmentation");
    ("--indirect", Arg.Set enable_indirect, "Enable Indirect Jump Tables (Computed Dispatch)");
    ("--lut", Arg.Set enable_lut, "Enable Lookup Table Arithmetic (LUT)");
    ("--interleave", Arg.Set enable_interleave, "Enable Array Folding & Interleaving");
    ("--permute-struct", Arg.Set enable_permute_struct, "Enable Struct Field Permutation & Padding");
    ("--pointer-mask", Arg.Set enable_pointer_mask, "Enable Pointer Swizzling & Masking");
    ("--homomorphic", Arg.Set enable_homomorphic, "Enable Homomorphic Data Encoding");
    ("--virtualize", Arg.Set enable_virtualize, "Enable random_vISA VCPU Bytecode Virtualization");
    ("--nested-vm", Arg.Set enable_nested_vm, "Enable Nested Multi-Layer VM");
    ("--self-mod-vm", Arg.Set enable_self_mod_vm, "Enable Self-Modifying Bytecode VM");
    ("--jitify", Arg.Set enable_jitify, "Enable JIT Bytecode Machine Code Compilation");
    ("--literals", Arg.Set enable_literals, "Enable String Literal Encryption");
    ("--split", Arg.Set enable_split, "Enable Variable Splitting (EncodeData)");
    ("--implicit", Arg.Set enable_implicit, "Enable Signal-Driven Implicit Flow (SIGSEGV)");
    ("--sigfpe", Arg.Set enable_sigfpe, "Enable Arithmetic Exception Flow (SIGFPE)");
    ("--sigill", Arg.Set enable_sigill, "Enable Illegal Opcode Flow (SIGILL)");
    ("--threaded-flow", Arg.Set enable_threaded, "Enable Multi-Threaded Race Implicit Flow");
    ("--syscall-flow", Arg.Set enable_syscall, "Enable Syscall Error Return Flow");
    ("--merge", Arg.Set enable_merge, "Enable Function Merging");
    ("--outline", Arg.Set enable_outline, "Enable Function Outlining");
    ("--inline", Arg.Set enable_inline, "Enable Function Inlining");
    ("--call-flatten", Arg.Set enable_call_flatten, "Enable Call Graph Flattening (Indirect Calls)");
    ("--bogus-calls", Arg.Set enable_bogus_calls, "Enable Cross-Function Bogus Call Injection");
    ("--rename", Arg.Set enable_rename, "Enable Identifier Renaming / Symbol Hashing");
    ("--strip", Arg.Set enable_strip, "Enable Source Directives Stripping");
    ("--anti-debug", Arg.Set enable_anti_debug, "Enable Anti-Debug Injection (sysctl P_TRACED)");
    ("--anti-disasm", Arg.Set enable_anti_disasm, "Enable Anti-Disassembly (Junk Byte Desync)");
    ("--self-checksum", Arg.Set enable_self_checksum, "Enable Self-Checksumming (Hash Guards)");
    ("--timing-check", Arg.Set enable_timing_check, "Enable Timing Verification (Anti-Stepping)");
    ("--hook-detect", Arg.Set enable_hook_detect, "Enable Dynamic Hook Detection");
  ] in

  let usage_msg = "Usage: ocasorry [-i <input.c> -o <output.c> [passes]] (run without args for interactive demo)" in
  Arg.parse speclist (fun _ -> ()) usage_msg;

  if !in_file = "" then
    run_demo ()
  else
    let target_out = if !out_file = "" then !in_file ^ ".obf.c" else !out_file in
    let config : Obfuscate_c_source_usecase.c_pipeline_config = {
      enable_c_mba = !enable_mba;
      enable_c_polynomial_mba = !enable_poly_mba;
      enable_c_opaque = !enable_opaque;
      enable_c_dynamic_opaque = !enable_dyn_opaque;
      enable_c_bogus_cf = !enable_bcf;
      enable_c_loop_unroll = !enable_unroll;
      enable_c_loop_fission = !enable_fission;
      enable_c_indirect_jump = !enable_indirect;
      enable_c_flattening = !enable_cff;
      enable_c_encode_literals = !enable_literals;
      enable_c_implicit_flow = !enable_implicit;
      enable_c_sigfpe_flow = !enable_sigfpe;
      enable_c_sigill_flow = !enable_sigill;
      enable_c_threaded_flow = !enable_threaded;
      enable_c_syscall_flow = !enable_syscall;
      enable_c_encode_data = !enable_split;
      enable_c_merge = !enable_merge;
      enable_c_outline = !enable_outline;
      enable_c_inline = !enable_inline;
      enable_c_call_flatten = !enable_call_flatten;
      enable_c_bogus_calls = !enable_bogus_calls;
      enable_c_rename_symbols = !enable_rename;
      enable_c_strip_directives = !enable_strip;
      enable_c_anti_debug = !enable_anti_debug;
      enable_c_anti_disasm = !enable_anti_disasm;
      enable_c_self_checksum = !enable_self_checksum;
      enable_c_timing_check = !enable_timing_check;
      enable_c_hook_detect = !enable_hook_detect;
      enable_c_lut = !enable_lut;
      enable_c_array_interleave = !enable_interleave;
      enable_c_struct_permute = !enable_permute_struct;
      enable_c_pointer_mask = !enable_pointer_mask;
      enable_c_homomorphic = !enable_homomorphic;
      enable_c_virtualize = !enable_virtualize;
      enable_c_nested_vm = !enable_nested_vm;
      enable_c_self_mod_vm = !enable_self_mod_vm;
      enable_c_jitify = !enable_jitify;
    } in
    Printf.printf "[*] Obfuscating: %s -> %s\n%!" !in_file target_out;
    CilSourceObfuscator.obfuscate_c_file !in_file target_out config;
    Printf.printf "[+] Done! Obfuscated C source generated successfully.\n%!"
