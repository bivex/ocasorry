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
  Suite_two_tier_jit.run ();
  Suite_polynomial_mba.run ();
  Suite_merge_functions.run ();
  Suite_outline.run ();
  Suite_dynamic_opaque.run ();
  Suite_bogus_control_flow.run ();
  Suite_loop_unroll.run ();
  Suite_loop_fission.run ();
  Suite_indirect_jump.run ();
  Suite_lut.run ();
  Suite_array_interleave.run ();
  Suite_struct_permute.run ();
  Suite_pointer_mask.run ();
  Suite_homomorphic.run ();
  Suite_virtualize.run ();
  Suite_nested_vm.run ();
  Suite_self_mod_vm.run ();
  Suite_jitify.run ();

  Printf.printf "\n=================================================================\n";
  Printf.printf "       ALL 25 MODULAR TEST SUITES PASSED SUCCESSFULLY!           \n";
  Printf.printf "=================================================================\n%!"
