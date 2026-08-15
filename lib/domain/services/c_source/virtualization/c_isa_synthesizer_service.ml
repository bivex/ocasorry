open C_visa_spec_service

(** Domain Service: Native DDD Multi-VCPU & Formal Sail Architecture Synthesizer
    Generates randomized formal Sail-compatible ISA specifications and JSON schemas for OcaSorry.
    Eliminates external Python scripts and provides 100% native OCaml compilation.
*)
module Make (Entropy : Entropy_port.S) = struct

  let shuffle (arr : 'a array) : unit =
    let len = Array.length arr in
    for i = len - 1 downto 1 do
      let j = Entropy.next_int ~max:(i + 1) in
      let tmp = arr.(i) in
      arr.(i) <- arr.(j);
      arr.(j) <- tmp
    done

  (* ============================================================================== *)
  (* VCPU 1: random_vISA (32-bit Vector ISA)                                        *)
  (* ============================================================================== *)
  let generate_random_visa ?(name : string option) ?(tier : int = 1) () :
      VisaSpec.visa_spec * string * string =
    let isa_id = 0x1000 + Entropy.next_int ~max:0xEFFF in
    let isa_name =
      match name with
      | Some n -> n
      | None -> Printf.sprintf "vISA_Vector_Arch_%04X" isa_id
    in
    let base_opcodes = [| 0x57; 0x0B; 0x2B; 0x7B; 0x37; 0x67 |] in
    let base_opcode = base_opcodes.(Entropy.next_int ~max:(Array.length base_opcodes)) in

    let funct6_pool = Array.init 64 (fun i -> i) in
    shuffle funct6_pool;
    let pool_idx = ref 0 in
    let pop () =
      let v = funct6_pool.(!pool_idx) in
      incr pool_idx;
      v
    in

    let op_vadd_vv = pop () in
    let op_vsub_vv = pop () in
    let op_vmul_vv = pop () in
    let op_vxor_vv = pop () in
    let op_vand_vv = pop () in
    let op_vor_vv  = pop () in
    let op_vsll_vv = pop () in
    let op_vsrl_vv = pop () in
    let op_vli_vi  = pop () in
    let op_vmv_vv  = pop () in
    let op_vle8_v  = pop () in
    let op_vse8_v  = pop () in
    let op_vret_v  = pop () in
    let op_vbge_vv = pop () in
    let _op_vblt_vv = pop () in
    let _op_vbeq_vv = pop () in
    let _op_vbne_vv = pop () in
    let op_vj      = pop () in

    let pack_key = Int64.logand (Int64.abs (Entropy.next_int64 ())) 0xFFFFFFFFL in
    let delta_keys = [| 0x1000193L; 0x9E3779B9L; 0x045D9F3BL; 0x21F0AAADL |] in
    let delta_key = delta_keys.(Entropy.next_int ~max:(Array.length delta_keys)) in

    let layout : VisaSpec.visa_field_layout = {
      funct6_shift = 26;
      funct6_mask = 0x3F;
      vm_shift = 25;
      vs2_shift = 20;
      vs1_shift = 15;
      funct3_shift = 12;
      vd_shift = 7;
      opcode_val = base_opcode;
    } in

    let opcodes : VisaSpec.visa_opcodes = {
      vadd_vv = op_vadd_vv;
      vsub_vv = op_vsub_vv;
      vmul_vv = op_vmul_vv;
      vxor_vv = op_vxor_vv;
      vand_vv = op_vand_vv;
      vor_vv  = op_vor_vv;
      vsll_vv = op_vsll_vv;
      vsrl_vv = op_vsrl_vv;
      vli_vi  = op_vli_vi;
      vmv_vv  = op_vmv_vv;
      vle8_v  = op_vle8_v;
      vse8_v  = op_vse8_v;
      vret_v  = op_vret_v;
      vbge_vv = op_vbge_vv;
      vj      = op_vj;
    } in
    let in_regs_arr = [| 0; 1; 2; 3; 4; 5; 6; 7 |] in
    shuffle in_regs_arr;
    let in_regs = Array.to_list in_regs_arr in
    let out_reg = Entropy.next_int ~max:4 in
    let abi : VisaSpec.visa_abi = { in_regs; out_reg } in

    let spec : VisaSpec.visa_spec = {
      isa_name;
      isa_version = "2.0";
      word_bits = 32;
      reg_count = 16;
      pack_key;
      delta_key;
      layout;
      opcodes;
      abi;
    } in

    let json_str = Format.sprintf {|{
  "vcpu_tier": %d,
  "vcpu_type": "visa",
  "isa_name": "%s",
  "isa_version": "2.0",
  "word_bits": 32,
  "reg_count": 16,
  "pack_key": %Ld,
  "delta_key": %Ld,
  "abi": {
    "in_regs": [%s],
    "out_reg": %d
  },
  "layout": {
    "funct6_shift": 26,
    "funct6_mask": 63,
    "vm_shift": 25,
    "vs2_shift": 20,
    "vs1_shift": 15,
    "funct3_shift": 12,
    "vd_shift": 7,
    "opcode_val": %d
  },
  "bitfields": {
    "funct6": {"msb": 31, "lsb": 26, "bits": 6},
    "vm": {"msb": 25, "lsb": 25, "bits": 1},
    "vs2": {"msb": 24, "lsb": 20, "bits": 5},
    "vs1": {"msb": 19, "lsb": 15, "bits": 5},
    "funct3": {"msb": 14, "lsb": 12, "bits": 3},
    "vd": {"msb": 11, "lsb": 7, "bits": 5},
    "opcode": {"msb": 6, "lsb": 0, "bits": 7}
  },
  "opcodes": {
    "vadd_vv": %d,
    "vsub_vv": %d,
    "vmul_vv": %d,
    "vxor_vv": %d,
    "vand_vv": %d,
    "vor_vv": %d,
    "vsll_vv": %d,
    "vsrl_vv": %d,
    "vli_vi": %d,
    "vmv_vv": %d,
    "vle8_v": %d,
    "vse8_v": %d,
    "vret_v": %d,
    "vbge_vv": %d,
    "vblt_vv": %d,
    "vbeq_vv": %d,
    "vbne_vv": %d,
    "vj": %d
  }
}|} tier isa_name pack_key delta_key (String.concat ", " (List.map string_of_int in_regs)) out_reg base_opcode
      op_vadd_vv op_vsub_vv op_vmul_vv op_vxor_vv op_vand_vv op_vor_vv
      op_vsll_vv op_vsrl_vv op_vli_vi op_vmv_vv op_vle8_v op_vse8_v
      op_vret_v op_vbge_vv _op_vblt_vv _op_vbeq_vv _op_vbne_vv op_vj
    in

    let sail_str =
      C_isa_sail_templates.render_visa_sail
        ~isa_name
        ~tier
        ~op_vadd_vv
        ~op_vsub_vv
        ~op_vmul_vv
        ~op_vxor_vv
        ~op_vand_vv
        ~op_vor_vv
        ~op_vsll_vv
        ~op_vsrl_vv
        ~op_vli_vi
        ~op_vmv_vv
        ~op_vle8_v
        ~op_vret_v
        ~op_vbge_vv
        ~op_vj
    in

    (spec, json_str, sail_str)

  (* ============================================================================== *)
  (* VCPU 2: nested_vm (2-Tier Hierarchical Nested VM)                              *)
  (* ============================================================================== *)
  let generate_nested_vm ?(name : string option) () : string * string =
    let vm_id = 0x1000 + Entropy.next_int ~max:0xEFFF in
    let vm_name =
      match name with
      | Some n -> n
      | None -> Printf.sprintf "NestedVM_2Tier_Arch_%04X" vm_id
    in
    let outer_key = 0x50 + Entropy.next_int ~max:0x5A in
    let inner_key = 0x80 + Entropy.next_int ~max:0x6E in

    let json_str = Format.sprintf {|{
  "vcpu_tier": 2,
  "vcpu_type": "nested_vm",
  "isa_name": "%s",
  "isa_version": "2.0",
  "outer_key": %d,
  "inner_key": %d,
  "outer_opcodes": {
    "op_out_setup": 16,
    "op_out_dispatch": 48,
    "op_out_mutate_key": 32,
    "op_out_halt": 255
  },
  "inner_opcodes": {
    "op_in_load_arg": 1,
    "op_in_load_const": 2,
    "op_in_add": 3,
    "op_in_sub": 4,
    "op_in_xor": 5,
    "op_in_mul": 6,
    "op_in_ret": 15
  }
}|} vm_name outer_key inner_key in

    let sail_str = C_isa_sail_templates.render_nested_vm_sail ~vm_name in
    (json_str, sail_str)

  (* ============================================================================== *)
  (* VCPU 3: rolling_vkey (Stateful History-Dependent Key VM)                       *)
  (* ============================================================================== *)
  let generate_rolling_vkey ?(name : string option) ?(tier : int = 3) () : string * string =
    let vm_id = 0x1000 + Entropy.next_int ~max:0xEFFF in
    let vm_name =
      match name with
      | Some n -> n
      | None -> Printf.sprintf "RollingVKey_Arch_%04X" vm_id
    in
    let vkey_seed = Int64.logand (Int64.abs (Entropy.next_int64 ())) 0xFFFFFFFFL in
    let lcg_mults = [| 33; 65; 31; 17 |] in
    let lcg_mult = lcg_mults.(Entropy.next_int ~max:(Array.length lcg_mults)) in
    let lcg_deltas = [| 0x9E3779B9L; 0x85EBCA6BL; 0xC2B2AE3DL |] in
    let lcg_delta = lcg_deltas.(Entropy.next_int ~max:(Array.length lcg_deltas)) in

    let json_str = Format.sprintf {|{
  "vcpu_tier": %d,
  "vcpu_type": "rolling_vkey",
  "isa_name": "%s",
  "vkey_seed": %Ld,
  "lcg_multiplier": %d,
  "lcg_delta": %Ld,
  "opcodes": {
    "op_add_imm": 1,
    "op_xor_imm": 2,
    "op_mul_imm": 3,
    "op_halt": 255
  }
}|} tier vm_name vkey_seed lcg_mult lcg_delta in

    let sail_str = C_isa_sail_templates.render_rolling_vkey_sail ~vm_name ~tier ~lcg_mult ~lcg_delta in
    (json_str, sail_str)

  (* ============================================================================== *)
  (* VCPU 4: ephemeral_jit (In-Memory Ephemeral JIT Wiper VM)                       *)
  (* ============================================================================== *)
  let generate_ephemeral_vm ?(name : string option) ?(tier : int = 4) () : string * string =
    let vm_id = 0x1000 + Entropy.next_int ~max:0xEFFF in
    let vm_name =
      match name with
      | Some n -> n
      | None -> Printf.sprintf "Ephemeral_JIT_Arch_%04X" vm_id
    in
    let session_key = 0x10 + Entropy.next_int ~max:0xEE in

    let json_str = Format.sprintf {|{
  "vcpu_tier": %d,
  "vcpu_type": "ephemeral_jit",
  "isa_name": "%s",
  "session_key": %d,
  "page_size": 4096,
  "opcodes": {
    "op_alloc_mmap": 16,
    "op_decrypt": 32,
    "op_execute": 48,
    "op_free_zero": 64
  }
}|} tier vm_name session_key in

    let sail_str = C_isa_sail_templates.render_ephemeral_jit_sail ~vm_name ~tier in
    (json_str, sail_str)

  (* ============================================================================== *)
  (* File IO Helpers                                                                *)
  (* ============================================================================== *)
  let write_file (path : string) (content : string) : unit =
    let oc = open_out path in
    output_string oc content;
    close_out oc

  (* ============================================================================== *)
  (* 4-VCPU Cascade Synthesis                                                       *)
  (* ============================================================================== *)
  let synthesize_4vcpu_cascade ?(name : string option) ~(out_dir : string) () : unit =
    (try Unix.mkdir out_dir 0o755 with _ -> ());

    let visa_name = match name with Some n -> n | None -> "vISA_License_Cascade_Arch" in
    let (_, j1, s1) = generate_random_visa ~name:visa_name ~tier:1 () in
    write_file (Filename.concat out_dir "vcpu1_visa.json") j1;
    write_file (Filename.concat out_dir "vcpu1_visa.sail") s1;
    Printf.printf "[+] [VCPU 1] Synthesized %s -> %s/vcpu1_visa.json & .sail\n" visa_name out_dir;

    let (j2, s2) = generate_nested_vm ~name:"NestedVM_Hierarchical_Arch" () in
    write_file (Filename.concat out_dir "vcpu2_nested_vm.json") j2;
    write_file (Filename.concat out_dir "vcpu2_nested_vm.sail") s2;
    Printf.printf "[+] [VCPU 2] Synthesized NestedVM_Hierarchical_Arch -> %s/vcpu2_nested_vm.json & .sail\n" out_dir;

    let (j3, s3) = generate_rolling_vkey ~name:"RollingVKey_Stateful_Arch" ~tier:3 () in
    write_file (Filename.concat out_dir "vcpu3_rolling_vkey.json") j3;
    write_file (Filename.concat out_dir "vcpu3_rolling_vkey.sail") s3;
    Printf.printf "[+] [VCPU 3] Synthesized RollingVKey_Stateful_Arch -> %s/vcpu3_rolling_vkey.json & .sail\n" out_dir;

    let (j4, s4) = generate_ephemeral_vm ~name:"Ephemeral_JIT_Security_Arch" ~tier:4 () in
    write_file (Filename.concat out_dir "vcpu4_ephemeral_jit.json") j4;
    write_file (Filename.concat out_dir "vcpu4_ephemeral_jit.sail") s4;
    Printf.printf "[+] [VCPU 4] Synthesized Ephemeral_JIT_Security_Arch -> %s/vcpu4_ephemeral_jit.json & .sail\n" out_dir

  (* ============================================================================== *)
  (* 8-VCPU Federated Cascade Synthesis (without nested_vm)                         *)
  (* ============================================================================== *)
  let synthesize_8vcpu_cascade ~(out_dir : string) () : unit =
    (try Unix.mkdir out_dir 0o755 with _ -> ());

    let (_, j1, s1) = generate_random_visa ~name:"vISA_AES_ExpandKey_Arch" ~tier:1 () in
    write_file (Filename.concat out_dir "vcpu1_expand_key.json") j1;
    write_file (Filename.concat out_dir "vcpu1_expand_key.sail") s1;
    Printf.printf "[+] [VCPU 1] Synthesized vISA_AES_ExpandKey_Arch -> %s/vcpu1_expand_key.json & .sail\n" out_dir;

    let (j2, s2) = generate_rolling_vkey ~name:"RollingVKey_AES_SubBytesR1_Arch" ~tier:2 () in
    write_file (Filename.concat out_dir "vcpu2_sub_bytes_r1.json") j2;
    write_file (Filename.concat out_dir "vcpu2_sub_bytes_r1.sail") s2;
    Printf.printf "[+] [VCPU 2] Synthesized RollingVKey_AES_SubBytesR1_Arch -> %s/vcpu2_sub_bytes_r1.json & .sail\n" out_dir;

    let (_, j3, s3) = generate_random_visa ~name:"vISA_AES_ShiftMixR1_Arch" ~tier:3 () in
    write_file (Filename.concat out_dir "vcpu3_shift_mix_r1.json") j3;
    write_file (Filename.concat out_dir "vcpu3_shift_mix_r1.sail") s3;
    Printf.printf "[+] [VCPU 3] Synthesized vISA_AES_ShiftMixR1_Arch -> %s/vcpu3_shift_mix_r1.json & .sail\n" out_dir;

    let (j4, s4) = generate_rolling_vkey ~name:"RollingVKey_AES_FeistelR1_Arch" ~tier:4 () in
    write_file (Filename.concat out_dir "vcpu4_feistel_xor_r1.json") j4;
    write_file (Filename.concat out_dir "vcpu4_feistel_xor_r1.sail") s4;
    Printf.printf "[+] [VCPU 4] Synthesized RollingVKey_AES_FeistelR1_Arch -> %s/vcpu4_feistel_xor_r1.json & .sail\n" out_dir;
    let (j5, s5) = generate_rolling_vkey ~name:"RollingVKey_AES_SubBytesR2_Arch" ~tier:5 () in
    write_file (Filename.concat out_dir "vcpu5_sub_bytes_r2.json") j5;
    write_file (Filename.concat out_dir "vcpu5_sub_bytes_r2.sail") s5;
    Printf.printf "[+] [VCPU 5] Synthesized RollingVKey_AES_SubBytesR2_Arch -> %s/vcpu5_sub_bytes_r2.json & .sail\n" out_dir;
    let (_, j6, s6) = generate_random_visa ~name:"vISA_AES_ShiftMixR2_Arch" ~tier:6 () in
    write_file (Filename.concat out_dir "vcpu6_shift_mix_r2.json") j6;
    write_file (Filename.concat out_dir "vcpu6_shift_mix_r2.sail") s6;
    Printf.printf "[+] [VCPU 6] Synthesized vISA_AES_ShiftMixR2_Arch -> %s/vcpu6_shift_mix_r2.json & .sail\n" out_dir;
    let (j7, s7) = generate_rolling_vkey ~name:"RollingVKey_AES_FeistelR2_Arch" ~tier:7 () in
    write_file (Filename.concat out_dir "vcpu7_feistel_xor_r2.json") j7;
    write_file (Filename.concat out_dir "vcpu7_feistel_xor_r2.sail") s7;
    Printf.printf "[+] [VCPU 7] Synthesized RollingVKey_AES_FeistelR2_Arch -> %s/vcpu7_feistel_xor_r2.json & .sail\n" out_dir;
    let (j8, s8) = generate_ephemeral_vm ~name:"Ephemeral_JIT_AES_Finalize_Arch" ~tier:8 () in
    write_file (Filename.concat out_dir "vcpu8_ephemeral_finalize.json") j8;
    write_file (Filename.concat out_dir "vcpu8_ephemeral_finalize.sail") s8;
    Printf.printf "[+] [VCPU 8] Synthesized Ephemeral_JIT_AES_Finalize_Arch -> %s/vcpu8_ephemeral_finalize.json & .sail\n" out_dir

  (* ============================================================================== *)
  (* Single VCPU Synthesis                                                          *)
  (* ============================================================================== *)
  let synthesize_single ~(vcpu : string) ~(out_json : string) ?(out_sail : string option) ?(name : string option) () : unit =
    let (json_str, sail_str) =
      match vcpu with
      | "visa" ->
          let (_, j, s) = generate_random_visa ?name ~tier:1 () in
          (j, s)
      | "nested_vm" -> generate_nested_vm ?name ()
      | "rolling_vkey" -> generate_rolling_vkey ?name ~tier:3 ()
      | "ephemeral" -> generate_ephemeral_vm ?name ~tier:4 ()
      | other -> failwith (Printf.sprintf "Unknown VCPU architecture type: %s" other)
    in
    write_file out_json json_str;
    Printf.printf "[+] Synthesized JSON Spec -> %s\n" out_json;
    let sail_path =
      match out_sail with
      | Some s -> s
      | None ->
          if Filename.check_suffix out_json ".json" then
            (Filename.chop_suffix out_json ".json") ^ ".sail"
          else out_json ^ ".sail"
    in
    write_file sail_path sail_str;
    Printf.printf "[+] Formal Sail Architecture Spec -> %s\n" sail_path
end
