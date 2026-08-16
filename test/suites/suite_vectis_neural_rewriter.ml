open Vectis_lib
open Vectis_ir
open Vectis_neural_rewriter
open Helpers

let run () =
  Printf.printf "\n--- [Suite 70] Vectis Next Neural Rewriter & Soundness Verifier Tests ---\n%!";

  let x = Var ("x", I64) in
  let y = Var ("y", I64) in
  let expr = BinOp (Xor, x, y, I64) in

  let res = Engine.rewrite expr ~mode:Engine.NeuralAssisted () in
  Printf.printf "  Rewrite debug: success=%b, verified=%b, final_exp=%s\n%!" res.success res.verified (to_string res.final_exp);
  assert_bool "Neural-assisted rewrite succeeded" res.success;
  assert_bool "Rewrite is formally verified" res.verified;


  let env = Hashtbl.create 4 in
  Hashtbl.replace env "x" 42L;
  Hashtbl.replace env "y" 1337L;
  let v_orig = eval env expr in
  let v_rewritten = eval env res.final_exp in
  assert_eq "Semantic equivalence on test vector" v_orig v_rewritten
