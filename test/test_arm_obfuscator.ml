open Ocasorry_lib
open Types
open Ast
open Cfg

module JIT = Jit_runner_usecase.Make
    (System_entropy_adapter.Adapter)
    (Aarch64_encoder_adapter.Adapter)
    (Posix_mmap_adapter.Adapter)

let assert_eq msg expected actual =
  if expected <> actual then (
    Printf.eprintf "[FAIL] %s: expected %Ld, got %Ld\n" msg expected actual;
    flush stderr;
    exit 1
  ) else (
    Printf.printf "[PASS] %s (result: %Ld)\n" msg actual;
    flush stdout
  )

(** Test 1: Linear computation f(x, y) = x + y *)
let test_add () =
  let block =
    BasicBlock.create
      ~id:"entry"
      ~instructions:[
        Add (X0, X0, X1);
        Ret None;
      ]
  in
  let cfg = CFG.create ~entry:"entry" ~blocks:[ block ] in
  let test_cases = [ (10L, 20L); (0L, 0L); (1000L, 4242L); (99999L, 1L) ] in
  List.iter
    (fun (x, y) ->
      let expected = Int64.add x y in
      (* Obfuscate with full pipeline *)
      let config : Obfuscation_pipeline.pipeline_config = {
        enable_mba = true;
        enable_opaque = true;
        enable_flattening = true;
      } in
      match JIT.obfuscate_and_run_fn2 cfg x y config with
      | Ok res -> assert_eq (Printf.sprintf "test_add(%Ld, %Ld)" x y) expected res.result_val
      | Error err -> failwith ("JIT error: " ^ err))
    test_cases

(** Test 2: Subtraction f(x, y) = x - y with MBA *)
let test_sub_mba () =
  let block =
    BasicBlock.create
      ~id:"entry"
      ~instructions:[
        Sub (X0, X0, X1);
        Ret None;
      ]
  in
  let cfg = CFG.create ~entry:"entry" ~blocks:[ block ] in
  let test_cases = [ (50L, 20L); (100L, 100L); (12345L, 6789L) ] in
  List.iter
    (fun (x, y) ->
      let expected = Int64.sub x y in
      let config : Obfuscation_pipeline.pipeline_config = {
        enable_mba = true;
        enable_opaque = false;
        enable_flattening = false;
      } in
      match JIT.obfuscate_and_run_fn2 cfg x y config with
      | Ok res -> assert_eq (Printf.sprintf "test_sub_mba(%Ld, %Ld)" x y) expected res.result_val
      | Error err -> failwith ("JIT error: " ^ err))
    test_cases

(** Test 3: Multi-block Control Flow with Flattening *)
let test_multiblock_flattening () =
  let b1 =
    BasicBlock.create
      ~id:"b1"
      ~instructions:[
        Add (X0, X0, X1);
        B "b2";
      ]
  in
  let b2 =
    BasicBlock.create
      ~id:"b2"
      ~instructions:[
        MovImm (X2, 1337L);
        Add (X0, X0, X2);
        B "b3";
      ]
  in
  let b3 =
    BasicBlock.create
      ~id:"b3"
      ~instructions:[
        Eor (X0, X0, X2);
        Ret None;
      ]
  in
  let cfg = CFG.create ~entry:"b1" ~blocks:[ b1; b2; b3 ] in
  let x = 42L in
  let y = 58L in
  let step1 = Int64.add x y in
  let step2 = Int64.add step1 1337L in
  let expected = Int64.logxor step2 1337L in
  let config = Obfuscation_pipeline.default_config in
  match JIT.obfuscate_and_run_fn2 cfg x y config with
  | Ok res -> assert_eq "test_multiblock_flattening" expected res.result_val
  | Error err -> failwith ("JIT error: " ^ err)

let () =
  Printf.printf "=== Running ARM64 Obfuscator Test Suite ===\n";
  flush stdout;
  test_add ();
  test_sub_mba ();
  test_multiblock_flattening ();
  Printf.printf "=== All 8 tests passed successfully! ===\n";
  flush stdout
