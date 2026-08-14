let () =
  Printf.printf "=================================================================\n";
  Printf.printf "      Running Comprehensive OcaSorry Test Suite (All Targets)    \n";
  Printf.printf "=================================================================\n%!";

  Suite_arm64_jit.run ();
  Suite_cil_bytecode.run ();
  Suite_c_source.run ();
  Suite_encode_literals.run ();
  Suite_implicit_flow.run ();
  Suite_variable_splitting.run ();
  Suite_compiler_wrapper.run ();

  Printf.printf "\n=================================================================\n";
  Printf.printf "       ALL 7 MODULAR TEST SUITES PASSED SUCCESSFULLY!            \n";
  Printf.printf "=================================================================\n%!"
