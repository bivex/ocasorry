open Vectis_lib
open Types
open Ast
open Cfg
open Helpers

let run () =
  Printf.printf "\n--- [Suite 1] AArch64 Native JIT Obfuscation Tests ---\n%!";

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
