open C_visa_spec_service

(** Domain Service: Native DDD Multi-VCPU & Formal Sail Architecture Synthesizer
    Generates randomized formal Sail-compatible ISA specifications and JSON schemas for Vectis.
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

  (* Random field layout: order the fused (vd+funct3) pair, vm, vs2 and vs1
     over the free window [25:7]. 4! = 24 equiprobable arrangements remove the
     fixed decoder skeleton while preserving every encoding invariant (see
     C_visa_spec.validate_layout). funct6 stays at [31:26]; the 19-bit
     jump window remains contiguous by construction. *)
  let random_layout ~(base_opcode : int) () : VisaSpec.visa_field_layout =
    let blocks = Entropy.shuffle [ ("pair", 8); ("vm", 1); ("vs2", 5); ("vs1", 5) ] in
    let pos = ref 7 in
    let shift_of = Hashtbl.create 4 in
    List.iter
      (fun (blk, width) ->
        Hashtbl.replace shift_of blk !pos;
        pos := !pos + width)
      blocks;
    let at blk = Hashtbl.find shift_of blk in
    let vd_shift = at "pair" in
    let layout : VisaSpec.visa_field_layout = {
      funct6_shift = 26;
      funct6_mask = 0x3F;
      vm_shift = at "vm";
      vs2_shift = at "vs2";
      vs1_shift = at "vs1";
      funct3_shift = vd_shift + 5;
      vd_shift;
      opcode_val = base_opcode;
    } in
    VisaSpec.validate_layout layout;
    layout

  let generate_random_visa ?(name : string option) ?(tier : int = 1)
      ?(params : C_isa_sail_templates.synth_params = C_isa_sail_templates.default_params) () :
      VisaSpec.visa_spec * string * string =
    let isa_id = 0x1000 + Entropy.next_int ~max:0xEFFF in
    let isa_name =
      match name with
      | Some n -> n
      | None -> Printf.sprintf "vISA_Vector_Arch_%04X" isa_id
    in
    (* Full 7-bit opcode space: the C runtime dispatches on funct6 only, so
       any base opcode ≤ 0x7F is sound (validate_layout range-checks). *)
    let base_opcode = Entropy.next_int ~max:0x80 in

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
    let op_vadd_alt1 = pop () in
    let op_vadd_alt2 = pop () in
    let op_vsub_alt1 = pop () in
    let op_vsub_alt2 = pop () in
    let op_vxor_alt1 = pop () in
    let op_vxor_alt2 = pop () in
    let op_vand_alt1 = pop () in
    let op_vor_alt1  = pop () in
    let op_vmul_alt1 = pop () in
    let op_vmv_alt1  = pop () in
    let op_vli_alt1  = pop () in

    let pack_key = Int64.logand (Int64.abs (Entropy.next_int64 ())) 0xFFFFFFFFL in
    (* Random odd nonzero 32-bit delta (odd for diffusion; the Z3 verifier
       only requires delta_key <> 0). Replaces the 4-entry constant pool. *)
    let rec draw_delta_key () =
      let d = Int64.logor (Int64.logand (Int64.abs (Entropy.next_int64 ())) 0xFFFFFFFFL) 1L in
      if d = 0L then draw_delta_key () else d
    in
    let delta_key = draw_delta_key () in

    let layout = random_layout ~base_opcode () in

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
      vadd_alt1 = op_vadd_alt1;
      vadd_alt2 = op_vadd_alt2;
      vsub_alt1 = op_vsub_alt1;
      vsub_alt2 = op_vsub_alt2;
      vxor_alt1 = op_vxor_alt1;
      vxor_alt2 = op_vxor_alt2;
      vand_alt1 = op_vand_alt1;
      vor_alt1  = op_vor_alt1;
      vmul_alt1 = op_vmul_alt1;
      vmv_alt1  = op_vmv_alt1;
      vli_alt1  = op_vli_alt1;
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
  "abi": {"in_regs": [%s], "out_reg": %d},
  "layout": {"funct6_shift": %d, "funct6_mask": %d, "vm_shift": %d, "vs2_shift": %d, "vs1_shift": %d, "funct3_shift": %d, "vd_shift": %d, "opcode_val": %d},
  "opcodes": {
    "vadd_vv": %d, "vsub_vv": %d, "vmul_vv": %d, "vxor_vv": %d, "vand_vv": %d, "vor_vv": %d,
    "vsll_vv": %d, "vsrl_vv": %d, "vli_vi": %d, "vmv_vv": %d, "vle8_v": %d, "vse8_v": %d,
    "vret_v": %d, "vbge_vv": %d, "vj": %d,
    "vadd_alt1": %d, "vadd_alt2": %d, "vsub_alt1": %d, "vsub_alt2": %d,
    "vxor_alt1": %d, "vxor_alt2": %d, "vand_alt1": %d, "vor_alt1": %d,
    "vmul_alt1": %d, "vmv_alt1": %d, "vli_alt1": %d
  }
}|} tier isa_name pack_key delta_key (String.concat ", " (List.map string_of_int in_regs)) out_reg
      layout.funct6_shift layout.funct6_mask layout.vm_shift layout.vs2_shift
      layout.vs1_shift layout.funct3_shift layout.vd_shift base_opcode
      op_vadd_vv op_vsub_vv op_vmul_vv op_vxor_vv op_vand_vv op_vor_vv
      op_vsll_vv op_vsrl_vv op_vli_vi op_vmv_vv op_vle8_v op_vse8_v
      op_vret_v op_vbge_vv op_vj
      op_vadd_alt1 op_vadd_alt2 op_vsub_alt1 op_vsub_alt2
      op_vxor_alt1 op_vxor_alt2 op_vand_alt1 op_vor_alt1
      op_vmul_alt1 op_vmv_alt1 op_vli_alt1
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
        ~vd_shift:layout.vd_shift
        ~vs1_shift:layout.vs1_shift
        ~vs2_shift:layout.vs2_shift
        ~rng:(fun () -> Entropy.next_int ~max:0x3FFFFFFF)
        ~params
    in

    (spec, json_str, sail_str)

  (* ============================================================================== *)
  (* VCPU 2: nested_vm (2-Tier Hierarchical Nested VM)                              *)
  (* ============================================================================== *)
  let generate_nested_vm ?(name : string option)
      ?(params : C_isa_sail_templates.synth_params = C_isa_sail_templates.default_params) () :
      string * string =
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

    let sail_str = C_isa_sail_templates.render_nested_vm_sail ~vm_name
        ~rng:(fun () -> Entropy.next_int ~max:0x3FFFFFFF) ~params in
    (json_str, sail_str)

  (* ============================================================================== *)
  (* VCPU 3: rolling_vkey (Stateful History-Dependent Key VM)                       *)
  (* ============================================================================== *)
  let generate_rolling_vkey ?(name : string option) ?(tier : int = 3)
      ?(params : C_isa_sail_templates.synth_params = C_isa_sail_templates.default_params) () :
      string * string =
    let vm_id = 0x1000 + Entropy.next_int ~max:0xEFFF in
    let vm_name =
      match name with
      | Some n -> n
      | None -> Printf.sprintf "RollingVKey_Arch_%04X" vm_id
    in
    let vkey_seed = Int64.logand (Int64.abs (Entropy.next_int64 ())) 0xFFFFFFFFL in
    (* Random odd multiplier/delta (invertible mod 2^32); ML overrides
       (--lcg-mult / --lcg-delta) are clamped and odd-forced. *)
    let lcg_mult =
      match params.lcg_mult with
      | Some v -> C_isa_sail_templates.clamp v 17 65535 lor 1
      | None -> (17 + Entropy.next_int ~max:0xFE01) lor 1
    in
    let lcg_delta =
      match params.lcg_delta with
      | Some v ->
          Int64.logor (Int64.logand v 0xFFFFFFFEL) 1L
      | None ->
          Int64.logor (Int64.logand (Int64.abs (Entropy.next_int64 ())) 0xFFFFFFFEL) 1L
    in

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

    let sail_str = C_isa_sail_templates.render_rolling_vkey_sail ~vm_name ~tier ~lcg_mult ~lcg_delta
        ~rng:(fun () -> Entropy.next_int ~max:0x3FFFFFFF) ~params in
    (json_str, sail_str)

  (* ============================================================================== *)
  (* VCPU 4: ephemeral_jit (In-Memory Ephemeral JIT Wiper VM)                       *)
  (* ============================================================================== *)
  let generate_ephemeral_vm ?(name : string option) ?(tier : int = 4)
      ?(params : C_isa_sail_templates.synth_params = C_isa_sail_templates.default_params) () :
      string * string =
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

    let sail_str = C_isa_sail_templates.render_ephemeral_jit_sail ~vm_name ~tier
        ~rng:(fun () -> Entropy.next_int ~max:0x3FFFFFFF) ~params in
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
  let synthesize_4vcpu_cascade ?(name : string option)
      ?(params : C_isa_sail_templates.synth_params = C_isa_sail_templates.default_params)
      ~(out_dir : string) () : unit =
    (try Unix.mkdir out_dir 0o755 with _ -> ());

    let visa_name = match name with Some n -> n | None -> "vISA_License_Cascade_Arch" in
    let (_, j1, s1) = generate_random_visa ~name:visa_name ~tier:1 ~params () in
    write_file (Filename.concat out_dir "vcpu1_visa.json") j1;
    write_file (Filename.concat out_dir "vcpu1_visa.sail") s1;
    Printf.printf "[+] [VCPU 1] Synthesized %s -> %s/vcpu1_visa.json & .sail\n" visa_name out_dir;

    let (j2, s2) = generate_nested_vm ~name:"NestedVM_Hierarchical_Arch" ~params () in
    write_file (Filename.concat out_dir "vcpu2_nested_vm.json") j2;
    write_file (Filename.concat out_dir "vcpu2_nested_vm.sail") s2;
    Printf.printf "[+] [VCPU 2] Synthesized NestedVM_Hierarchical_Arch -> %s/vcpu2_nested_vm.json & .sail\n" out_dir;

    let (j3, s3) = generate_rolling_vkey ~name:"RollingVKey_Stateful_Arch" ~tier:3 ~params () in
    write_file (Filename.concat out_dir "vcpu3_rolling_vkey.json") j3;
    write_file (Filename.concat out_dir "vcpu3_rolling_vkey.sail") s3;
    Printf.printf "[+] [VCPU 3] Synthesized RollingVKey_Stateful_Arch -> %s/vcpu3_rolling_vkey.json & .sail\n" out_dir;

    let (j4, s4) = generate_ephemeral_vm ~name:"Ephemeral_JIT_Security_Arch" ~tier:4 ~params () in
    write_file (Filename.concat out_dir "vcpu4_ephemeral_jit.json") j4;
    write_file (Filename.concat out_dir "vcpu4_ephemeral_jit.sail") s4;
    Printf.printf "[+] [VCPU 4] Synthesized Ephemeral_JIT_Security_Arch -> %s/vcpu4_ephemeral_jit.json & .sail\n" out_dir

  (* ============================================================================== *)
  (* 8-VCPU Federated Cascade Synthesis (without nested_vm)                         *)
  (* ============================================================================== *)
  let synthesize_8vcpu_cascade
      ?(params : C_isa_sail_templates.synth_params = C_isa_sail_templates.default_params)
      ~(out_dir : string) () : unit =
    (try Unix.mkdir out_dir 0o755 with _ -> ());

    let (_, j1, s1) = generate_random_visa ~name:"vISA_AES_ExpandKey_Arch" ~tier:1 ~params () in
    write_file (Filename.concat out_dir "vcpu1_expand_key.json") j1;
    write_file (Filename.concat out_dir "vcpu1_expand_key.sail") s1;
    Printf.printf "[+] [VCPU 1] Synthesized vISA_AES_ExpandKey_Arch -> %s/vcpu1_expand_key.json & .sail\n" out_dir;

    let (j2, s2) = generate_rolling_vkey ~name:"RollingVKey_AES_SubBytesR1_Arch" ~tier:2 ~params () in
    write_file (Filename.concat out_dir "vcpu2_sub_bytes_r1.json") j2;
    write_file (Filename.concat out_dir "vcpu2_sub_bytes_r1.sail") s2;
    Printf.printf "[+] [VCPU 2] Synthesized RollingVKey_AES_SubBytesR1_Arch -> %s/vcpu2_sub_bytes_r1.json & .sail\n" out_dir;

    let (_, j3, s3) = generate_random_visa ~name:"vISA_AES_ShiftMixR1_Arch" ~tier:3 ~params () in
    write_file (Filename.concat out_dir "vcpu3_shift_mix_r1.json") j3;
    write_file (Filename.concat out_dir "vcpu3_shift_mix_r1.sail") s3;
    Printf.printf "[+] [VCPU 3] Synthesized vISA_AES_ShiftMixR1_Arch -> %s/vcpu3_shift_mix_r1.json & .sail\n" out_dir;

    let (j4, s4) = generate_rolling_vkey ~name:"RollingVKey_AES_FeistelR1_Arch" ~tier:4 ~params () in
    write_file (Filename.concat out_dir "vcpu4_feistel_xor_r1.json") j4;
    write_file (Filename.concat out_dir "vcpu4_feistel_xor_r1.sail") s4;
    Printf.printf "[+] [VCPU 4] Synthesized RollingVKey_AES_FeistelR1_Arch -> %s/vcpu4_feistel_xor_r1.json & .sail\n" out_dir;
    let (j5, s5) = generate_rolling_vkey ~name:"RollingVKey_AES_SubBytesR2_Arch" ~tier:5 ~params () in
    write_file (Filename.concat out_dir "vcpu5_sub_bytes_r2.json") j5;
    write_file (Filename.concat out_dir "vcpu5_sub_bytes_r2.sail") s5;
    Printf.printf "[+] [VCPU 5] Synthesized RollingVKey_AES_SubBytesR2_Arch -> %s/vcpu5_sub_bytes_r2.json & .sail\n" out_dir;
    let (_, j6, s6) = generate_random_visa ~name:"vISA_AES_ShiftMixR2_Arch" ~tier:6 ~params () in
    write_file (Filename.concat out_dir "vcpu6_shift_mix_r2.json") j6;
    write_file (Filename.concat out_dir "vcpu6_shift_mix_r2.sail") s6;
    Printf.printf "[+] [VCPU 6] Synthesized vISA_AES_ShiftMixR2_Arch -> %s/vcpu6_shift_mix_r2.json & .sail\n" out_dir;
    let (j7, s7) = generate_rolling_vkey ~name:"RollingVKey_AES_FeistelR2_Arch" ~tier:7 ~params () in
    write_file (Filename.concat out_dir "vcpu7_feistel_xor_r2.json") j7;
    write_file (Filename.concat out_dir "vcpu7_feistel_xor_r2.sail") s7;
    Printf.printf "[+] [VCPU 7] Synthesized RollingVKey_AES_FeistelR2_Arch -> %s/vcpu7_feistel_xor_r2.json & .sail\n" out_dir;
    let (j8, s8) = generate_ephemeral_vm ~name:"Ephemeral_JIT_AES_Finalize_Arch" ~tier:8 ~params () in
    write_file (Filename.concat out_dir "vcpu8_ephemeral_finalize.json") j8;
    write_file (Filename.concat out_dir "vcpu8_ephemeral_finalize.sail") s8;
    Printf.printf "[+] [VCPU 8] Synthesized Ephemeral_JIT_AES_Finalize_Arch -> %s/vcpu8_ephemeral_finalize.json & .sail\n" out_dir

  (* ============================================================================== *)
  (* Single VCPU Synthesis                                                          *)
  (* ============================================================================== *)
  let synthesize_single ~(vcpu : string) ~(out_json : string) ?(out_sail : string option) ?(name : string option)
      ?(params : C_isa_sail_templates.synth_params = C_isa_sail_templates.default_params) () : unit =
    let (json_str, sail_str) =
      match vcpu with
      | "visa" ->
          let (_, j, s) = generate_random_visa ?name ~tier:1 ~params () in
          (j, s)
      | "nested_vm" -> generate_nested_vm ?name ~params ()
      | "rolling_vkey" -> generate_rolling_vkey ?name ~tier:3 ~params ()
      | "ephemeral" -> generate_ephemeral_vm ?name ~tier:4 ~params ()
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
