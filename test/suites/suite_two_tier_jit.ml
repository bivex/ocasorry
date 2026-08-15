open Vectis_lib
open Types
open Ast
open Cfg
open Helpers

module TwoTierJIT = Two_tier_jit_usecase.Make
    (System_entropy_adapter.Adapter)
    (Aarch64_encoder_adapter.Adapter)

let run () =
  Printf.printf "\n--- [Suite 8] Two-Level JITting + Hardware Implicit Flow Tests ---\n%!";

  let b1 = BasicBlock.create ~id:"b1" ~instructions:[ Add (X0, X0, X1); B "b2" ] in
  let b2 = BasicBlock.create ~id:"b2" ~instructions:[ MovImm (X2, 0x5A5AL); Eor (X0, X0, X2); Ret None ] in
  let cfg = CFG.create ~entry:"b1" ~blocks:[ b1; b2 ] in

  let test_cases = [
    (100L, 200L);
    (0L, 0L);
    (1337L, 42L);
    (999999L, 123456L);
  ] in

  List.iter
    (fun (x, y) ->
      let expected = Int64.logxor (Int64.add x y) 0x5A5AL in
      let config = Obfuscation_pipeline.default_config in
      match TwoTierJIT.execute_two_tier_fn2 cfg x y config with
      | Ok res ->
          assert_eq (Printf.sprintf "Two-Tier JIT + Implicit Flow f(%Ld, %Ld)" x y) expected res.result_val
      | Error err -> failwith ("Two-Tier JIT error: " ^ err))
    test_cases
