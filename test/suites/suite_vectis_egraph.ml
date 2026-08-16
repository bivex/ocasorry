open Vectis_lib
open Vectis_ir
open Vectis_egraph
open Helpers

let run () =
  Printf.printf "\n--- [Suite 69] Vectis Next E-Graph Equality Saturation Tests ---\n%!";

  let eg = create_egraph () in
  let a = Var ("a", I64) in
  let b = Var ("b", I64) in
  let expr = BinOp (Add, a, b, I64) in

  let root = insert_exp eg expr in
  let iters = saturate eg ~max_iters:3 () in
  assert_bool "Saturation performed iterations" (iters > 0);

  let extracted_complex = extract eg root ~target:MaximizeComplexity () in
  assert_bool "Complex extraction increases AST size" (exp_size extracted_complex > exp_size expr);

  let extracted_min = extract eg root ~target:MinimizeSize () in
  assert_bool "Minimal extraction is compact" (exp_size extracted_min <= exp_size extracted_complex)
