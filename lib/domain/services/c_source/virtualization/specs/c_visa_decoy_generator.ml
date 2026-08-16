open C_visa_spec

(** Vector 4: Decoy Bytecode & Virtual Path Explosion Generator
    Generates dead and misleading bytecode blocks guarded by unconditional or
    opaque jumps in the vISA instruction stream. Traps dynamic symbolic execution
    engines (angr, Triton, Pushan) in exponential state exploration.
*)
module Make (Entropy : Entropy_port.S) = struct

  let generate_random_decoy_instruction (spec : visa_spec) : int32 =
    let op = spec.opcodes in
    let funct6_choices = [|
      op.vadd_vv; op.vsub_vv; op.vmul_vv; op.vxor_vv;
      op.vand_vv; op.vor_vv; op.vsll_vv; op.vsrl_vv;
      op.vli_vi; op.vmv_vv; op.vle8_v; op.vse8_v;
      op.vret_v; op.vbge_vv; op.vjit_vv
    |] in
    let funct6 = funct6_choices.(Entropy.next_int ~max:(Array.length funct6_choices)) in
    let vm = Entropy.next_int ~max:2 in
    let vs2 = Entropy.next_int ~max:32 in
    let vs1 = Entropy.next_int ~max:32 in
    let funct3 = Entropy.next_int ~max:8 in
    let vd = Entropy.next_int ~max:32 in
    C_visa_spec.encode_inst spec ~funct6 ~vm ~vs2 ~vs1_or_imm:vs1 ~funct3 ~vd

  let emit_opaque_decoy_cluster
      (spec : visa_spec)
      (instrs : int32 list ref)
      ~(count : int) : unit =
    let current_pc = List.length !instrs in
    let target_pc = current_pc + count + 1 in
    let l = spec.layout in
    let op = spec.opcodes in
    (* Positional 19-bit jump window [25:7] — bottom is the opcode width,
       not vd_shift (mirrors C_visa_stmt_compiler.encode_jump). *)
    let vj_target_shift = 7 in
    let jump_word =
      (((op.vj land l.funct6_mask) lsl l.funct6_shift) lor
       ((target_pc land 0x7FFFF) lsl vj_target_shift) lor
       (l.opcode_val land 0x7F)) land 0xFFFFFFFF
    in
    instrs := (Int32.of_int jump_word) :: !instrs;
    for _ = 1 to count do
      instrs := (generate_random_decoy_instruction spec) :: !instrs
    done
end
