open Ocasorry_lib

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
    Printf.eprintf "[FAIL] %s: expected %Ld, got %Ld\n%!" msg expected actual;
    exit 1
  ) else (
    Printf.printf "  [PASS] %s (result: %Ld)\n%!" msg actual
  )

let assert_bool msg cond =
  if not cond then (
    Printf.eprintf "[FAIL] %s\n%!" msg;
    exit 1
  ) else (
    Printf.printf "  [PASS] %s\n%!" msg
  )

let find_wrapper_bin () =
  let candidate_paths = [
    "./_build/default/bin/ocasorry_cc.exe";
    "../bin/ocasorry_cc.exe";
    "./ocasorry_cc.exe";
    "/Volumes/External/Code/ocasorry/_build/default/bin/ocasorry_cc.exe";
  ] in
  List.find_opt Sys.file_exists candidate_paths
