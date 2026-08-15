open Vectis_lib
open Types
open Ast
open Cfg
open Helpers

let run () =
  Printf.printf "\n--- [Suite 2] ECMA-335 CIL Bytecode VM Tests ---\n%!";

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
