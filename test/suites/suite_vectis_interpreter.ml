open Vectis_lib
open Vectis_isa
open Vectis_vm_interpreter
open Helpers

let run () =
  Printf.printf "\n--- [Suite 68] Vectis Next VM Interpreter & State Masking Tests ---\n%!";

  let vm = create_vm ~reg_count:16 () in
  let insn0 = make_insn 0 OP_MOV (Some (Reg 1)) (Some (Imm 10L)) None in
  let insn1 = make_insn 1 OP_MOV (Some (Reg 2)) (Some (Imm 20L)) None in
  let insn2 = make_insn 2 OP_ADD (Some (Reg 0)) (Some (Reg 1)) (Some (Reg 2)) in
  let insn3 = make_insn 3 OP_XOR (Some (Reg 0)) (Some (Reg 0)) (Some (Imm 5L)) in
  let insn4 = make_insn 4 OP_RET None None None in

  let prog = {
    version = 1;
    arch_name = "Vectis_vISA_v2";
    reg_count = 16;
    instructions = [| insn0; insn1; insn2; insn3; insn4 |];
  } in

  (match run_vm vm prog with
  | Ok res ->
      assert_eq "VM arithmetic (10+20)^5 = 27" (Int64.logxor 30L 5L) res
  | Error err ->
      failwith ("VM execution failed: " ^ err));

  (* Test register state masking *)
  let vm2 = create_vm ~reg_count:8 () in
  set_reg vm2 1 0x123456789ABCDEF0L;
  let unmasked = get_reg vm2 1 in
  assert_eq "Unmasked register read" 0x123456789ABCDEF0L unmasked;
  let raw = vm2.reg_bank.(1) in
  assert_bool "Raw register value in memory is algebraic masked" (raw <> 0x123456789ABCDEF0L)
