open Ocasorry_lib
open Types
open Ast
open Cfg

(* Composition Root: Plug Adapters into Application Use Case *)
module JIT = Jit_runner_usecase.Make
    (System_entropy_adapter.Adapter)
    (Aarch64_encoder_adapter.Adapter)
    (Posix_mmap_adapter.Adapter)

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
  Printf.printf "  Size: %d bytes (%d instructions)\n  Hex: " len (len / 4);
  for i = 0 to len - 1 do
    Printf.printf "%02x " (Char.code (Bytes.get b i));
    if (i + 1) mod 16 = 0 && i + 1 < len then Printf.printf "\n       "
  done;
  Printf.printf "\n";
  flush stdout

let () =
  Printf.printf "========================================================\n";
  Printf.printf "  OcaSorry: AArch64 JIT Obfuscator (DDD Hexagonal Arch) \n";
  Printf.printf "========================================================\n\n";
  flush stdout;

  let x = 100L in
  let y = 200L in
  let expected = Int64.logxor (Int64.add x y) 0x5A5AL in
  Printf.printf "[1] Reference test input: x0 = %Ld, x1 = %Ld\n" x y;
  Printf.printf "    Expected output: (x0 + x1) ^ 0x5A5A = %Ld (0x%Lx)\n\n" expected expected;
  flush stdout;

  (* 1. Plain Compilation & JIT Execution *)
  let cfg_plain = build_sample_cfg () in
  let no_obf_config : Obfuscation_pipeline.pipeline_config = {
    enable_mba = false;
    enable_opaque = false;
    enable_flattening = false;
  } in
  Printf.printf "[2] Running Plain (Unobfuscated) AArch64 JIT Pipeline...\n";
  flush stdout;
  (match JIT.obfuscate_and_run_fn2 cfg_plain x y no_obf_config with
  | Ok res ->
      print_hex_dump res.raw_bytes;
      Printf.printf "    Execution result: %Ld (0x%Lx) -> %s\n\n"
        res.result_val res.result_val
        (if res.result_val = expected then "PASSED [OK]" else "FAILED [MISMATCH]");
      flush stdout
  | Error err ->
      Printf.printf "    Error: %s\n\n" err;
      flush stdout);

  (* 2. Full Obfuscation Pipeline: MBA + Opaque Predicates + Control Flow Flattening *)
  let cfg_obf = build_sample_cfg () in
  let full_obf_config : Obfuscation_pipeline.pipeline_config = {
    enable_mba = true;
    enable_opaque = true;
    enable_flattening = true;
  } in
  Printf.printf "[3] Running Obfuscated Pipeline (MBA + Opaque Predicates + CFF)...\n";
  flush stdout;
  match JIT.obfuscate_and_run_fn2 cfg_obf x y full_obf_config with
  | Ok res ->
      print_hex_dump res.raw_bytes;
      Printf.printf "    Execution result: %Ld (0x%Lx) -> %s\n\n"
        res.result_val res.result_val
        (if res.result_val = expected then "PASSED [OK]" else "FAILED [MISMATCH]");
      Printf.printf "========================================================\n";
      Printf.printf "  JIT Execution & Obfuscation Verification Complete!\n";
      Printf.printf "========================================================\n";
      flush stdout
  | Error err ->
      Printf.printf "    Error: %s\n" err;
      flush stdout
