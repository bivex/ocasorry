open Ocasorry_lib
open Types
open Ast
open Cfg

(* Composition Root 1: ARM64 Native JIT Runner *)
module ArmJIT = Jit_runner_usecase.Make
    (System_entropy_adapter.Adapter)
    (Aarch64_encoder_adapter.Adapter)
    (Posix_mmap_adapter.Adapter)

(* Composition Root 2: Portable ECMA-335 CIL Bytecode Runner *)
module CilJIT = Jit_runner_usecase.Make
    (System_entropy_adapter.Adapter)
    (Cil_encoder_adapter.Adapter)
    (Cil_vm_adapter.Adapter)

(** Builds a multi-block CFG computing: f(x0, x1) = (x0 + x1) ^ 0x5A5A *)
let build_sample_cfg () : CFG.t =
  let block1 =
    BasicBlock.create
      ~id:"block_entry"
      ~instructions:[
        Add (X0, X0, X1);          (* x0 = x0 + x1 *)
        MovImm (X2, 0x5A5AL);      (* x2 = 0x5a5a *)
        B "block_finish";          (* jump to finish *)
      ]
  in
  let block2 =
    BasicBlock.create
      ~id:"block_finish"
      ~instructions:[
        Eor (X0, X0, X2);          (* x0 = x0 ^ x2 *)
        Ret None;                  (* ret *)
      ]
  in
  CFG.create ~entry:"block_entry" ~blocks:[ block1; block2 ]

let print_hex_dump (b : bytes) =
  let len = Bytes.length b in
  Printf.printf "  Size: %d bytes\n  Hex: " len;
  for i = 0 to len - 1 do
    Printf.printf "%02x " (Char.code (Bytes.get b i));
    if (i + 1) mod 16 = 0 && i + 1 < len then Printf.printf "\n       "
  done;
  Printf.printf "\n";
  flush stdout

let () =
  Printf.printf "=================================================================\n";
  Printf.printf "  OcaSorry: Multi-Target Obfuscator (ARM64 Native & ECMA-335 CIL) \n";
  Printf.printf "=================================================================\n\n";
  flush stdout;

  let x = 100L in
  let y = 200L in
  let expected = Int64.logxor (Int64.add x y) 0x5A5AL in
  Printf.printf "[Input] x0 = %Ld, x1 = %Ld\n" x y;
  Printf.printf "[Expected Output] (x0 + x1) ^ 0x5A5A = %Ld (0x%Lx)\n\n" expected expected;
  flush stdout;

  let full_obf_config : Obfuscation_pipeline.pipeline_config = {
    enable_mba = true;
    enable_opaque = true;
    enable_flattening = true;
  } in

  (* 1. Target: AArch64 (ARM64) Apple Silicon Native JIT *)
  Printf.printf "-----------------------------------------------------------------\n";
  Printf.printf " [Target 1] AArch64 (ARM64) Machine Code JIT Pipeline\n";
  Printf.printf "-----------------------------------------------------------------\n";
  (match ArmJIT.obfuscate_and_run_fn2 (build_sample_cfg ()) x y full_obf_config with
  | Ok res ->
      print_hex_dump res.raw_bytes;
      Printf.printf "  Result: %Ld (0x%Lx) -> %s\n\n"
        res.result_val res.result_val
        (if res.result_val = expected then "PASSED [OK]" else "FAILED [MISMATCH]");
      flush stdout
  | Error err ->
      Printf.printf "  Error: %s\n\n" err;
      flush stdout);

  (* 2. Target: ECMA-335 CIL Bytecode VM Pipeline *)
  Printf.printf "-----------------------------------------------------------------\n";
  Printf.printf " [Target 2] ECMA-335 Common Intermediate Language (CIL) Pipeline\n";
  Printf.printf "-----------------------------------------------------------------\n";
  (match CilJIT.obfuscate_and_run_fn2 (build_sample_cfg ()) x y full_obf_config with
  | Ok res ->
      print_hex_dump res.raw_bytes;
      Printf.printf "  Result: %Ld (0x%Lx) -> %s\n\n"
        res.result_val res.result_val
        (if res.result_val = expected then "PASSED [OK]" else "FAILED [MISMATCH]");
      flush stdout
  | Error err ->
      Printf.printf "  Error: %s\n\n" err;
      flush stdout);

  Printf.printf "=================================================================\n";
  Printf.printf "  Multi-Target Hexagonal Obfuscator Execution Complete!\n";
  Printf.printf "=================================================================\n";
  flush stdout
