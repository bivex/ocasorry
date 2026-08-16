open Vectis_lib
open Vectis_isa
open Helpers

let run () =
  Printf.printf "\n--- [Suite 67] Vectis Next ISA Disassembly & Specification Tests ---\n%!";

  let insn1 = make_insn 0 OP_MOV (Some (Reg 0)) (Some (Imm 42L)) None in
  let insn2 = make_insn 1 OP_ADD (Some (Reg 0)) (Some (Reg 0)) (Some (Reg 1)) in
  let insn3 = make_insn ~cond:V_EQ 2 OP_BRANCH None (Some (Imm 100L)) None in
  let insn4 = make_insn 3 OP_RET None None None in

  let prog = {
    version = 1;
    arch_name = "Vectis_vISA_v2";
    reg_count = 32;
    instructions = [| insn1; insn2; insn3; insn4 |];
  } in

  let dis = disasm_program prog in
  assert_bool "Disassembly contains header" (String.length dis > 50);
  assert_bool "Disassembly contains MOV" (try ignore (Str.search_forward (Str.regexp "MOV") dis 0); true with _ -> false);
  assert_bool "Disassembly contains ADD" (try ignore (Str.search_forward (Str.regexp "ADD") dis 0); true with _ -> false);
  assert_bool "Disassembly contains BRANCH.EQ" (try ignore (Str.search_forward (Str.regexp "BRANCH\\.EQ") dis 0); true with _ -> false);
  assert_bool "Disassembly contains RET" (try ignore (Str.search_forward (Str.regexp "RET") dis 0); true with _ -> false)
