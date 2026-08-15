type c_pipeline_config = {
  enable_c_mba : bool;
  enable_c_polynomial_mba : bool;
  enable_c_float_mba : bool;
  enable_c_opaque : bool;
  enable_c_dynamic_opaque : bool;
  enable_c_diophantine : bool;
  enable_c_bogus_cf : bool;
  enable_c_basic_block_split : bool;
  enable_c_decentralized_disp : bool;
  enable_c_relational_morph : bool;
  enable_c_irreducible_loop : bool;
  enable_c_loop_unroll : bool;
  enable_c_loop_fission : bool;
  enable_c_loop_to_recursion : bool;
  enable_c_indirect_jump : bool;
  enable_c_flattening : bool;
  enable_c_encode_literals : bool;
  enable_c_implicit_flow : bool;
  enable_c_sigfpe_flow : bool;
  enable_c_sigill_flow : bool;
  enable_c_threaded_flow : bool;
  enable_c_syscall_flow : bool;
  enable_c_encode_data : bool;
  enable_c_merge : bool;
  enable_c_outline : bool;
  enable_c_inline : bool;
  enable_c_call_flatten : bool;
  enable_c_bogus_calls : bool;
  enable_c_rename_symbols : bool;
  enable_c_strip_directives : bool;
  enable_c_anti_debug : bool;
  enable_c_anti_disasm : bool;
  enable_c_self_checksum : bool;
  enable_c_timing_check : bool;
  enable_c_hook_detect : bool;
  enable_c_api_hash : bool;
  enable_c_early_constructor : bool;
  enable_c_rolling_vkey : bool;
  enable_c_vcpu_scramble : bool;
  enable_c_ephemeral_payload : bool;
  enable_c_instruction_subst : bool;
  enable_c_instruction_permute : bool;
  enable_c_ghost_code : bool;
  enable_c_live_range_split : bool;
  enable_c_constant_unfold : bool;
  enable_c_stack_aliasing : bool;
  enable_c_opcode_equalize : bool;
  enable_c_anti_slicing : bool;
  enable_c_lut : bool;
  enable_c_array_interleave : bool;
  enable_c_struct_permute : bool;
  enable_c_pointer_mask : bool;
  enable_c_homomorphic : bool;
  enable_c_virtualize : bool;
  enable_c_nested_vm : bool;
  enable_c_self_mod_vm : bool;
  enable_c_jitify : bool;
  enable_c_egraph_mba : bool;
  c_egraph_depth : int;
  enable_c_eh_shadow : bool;
  enable_c_loki_invariants : bool;
  enable_c_micro_dispatcher : bool;
  enable_c_anti_vtil : bool;
  c_vm_profile : string option;
}

let default_c_config = {
  enable_c_mba = true;
  enable_c_polynomial_mba = false;
  enable_c_float_mba = false;
  enable_c_egraph_mba = false;
  c_egraph_depth = 3;
  enable_c_eh_shadow = false;
  enable_c_loki_invariants = false;
  enable_c_micro_dispatcher = false;
  enable_c_anti_vtil = false;
  c_vm_profile = None;
  enable_c_opaque = true;
  enable_c_dynamic_opaque = false;
  enable_c_diophantine = false;
  enable_c_bogus_cf = false;
  enable_c_basic_block_split = false;
  enable_c_decentralized_disp = false;
  enable_c_relational_morph = false;
  enable_c_irreducible_loop = false;
  enable_c_loop_unroll = false;
  enable_c_loop_fission = false;
  enable_c_loop_to_recursion = false;
  enable_c_indirect_jump = false;
  enable_c_flattening = true;
  enable_c_encode_literals = false;
  enable_c_implicit_flow = false;
  enable_c_sigfpe_flow = false;
  enable_c_sigill_flow = false;
  enable_c_threaded_flow = false;
  enable_c_syscall_flow = false;
  enable_c_encode_data = false;
  enable_c_merge = false;
  enable_c_outline = false;
  enable_c_inline = false;
  enable_c_call_flatten = false;
  enable_c_bogus_calls = false;
  enable_c_rename_symbols = false;
  enable_c_strip_directives = false;
  enable_c_anti_debug = false;
  enable_c_anti_disasm = false;
  enable_c_self_checksum = false;
  enable_c_timing_check = false;
  enable_c_hook_detect = false;
  enable_c_api_hash = false;
  enable_c_early_constructor = false;
  enable_c_rolling_vkey = false;
  enable_c_vcpu_scramble = false;
  enable_c_ephemeral_payload = false;
  enable_c_instruction_subst = false;
  enable_c_instruction_permute = false;
  enable_c_ghost_code = false;
  enable_c_live_range_split = false;
  enable_c_constant_unfold = false;
  enable_c_stack_aliasing = false;
  enable_c_opcode_equalize = false;
  enable_c_anti_slicing = false;
  enable_c_lut = false;
  enable_c_array_interleave = false;
  enable_c_struct_permute = false;
  enable_c_pointer_mask = false;
  enable_c_homomorphic = false;
  enable_c_virtualize = false;
  enable_c_nested_vm = false;
  enable_c_self_mod_vm = false;
  enable_c_jitify = false;
}

module Make (Entropy : Entropy_port.S) (C_Port : C_source_port.S) = struct
  module MBA = C_mba_service.Make (Entropy)
  module PolyMBA = C_polynomial_mba_service.Make (Entropy)
  module FloatMBA = C_float_mba_service.Make (Entropy)
  module Opaque = C_opaque_service.Make (Entropy)
  module DynOpaque = C_dynamic_opaque_service.Make (Entropy)
  module Diophantine = C_diophantine_opaque_service.Make (Entropy)
  module BogusCF = C_bogus_control_flow_service.Make (Entropy)
  module BBSplit = C_basic_block_split_service.Make (Entropy)
  module DecentDisp = C_decentralized_dispatcher_service.Make (Entropy)
  module RelationalMorph = C_relational_morph_service.Make (Entropy)
  module IrreducibleLoop = C_irreducible_loop_service.Make (Entropy)
  module LoopUnroll = C_loop_unroll_service.Make (Entropy)
  module LoopFission = C_loop_fission_service.Make (Entropy)
  module LoopToRecursion = C_loop_to_recursion_service.Make (Entropy)
  module IndirectJump = C_indirect_jump_service.Make (Entropy)
  module Flattening = C_flattening_service.Make (Entropy)
  module EncodeLiterals = C_encode_literals_service.Make (Entropy)
  module ImplicitFlow = C_implicit_flow_service.Make (Entropy)
  module SigFPEFlow = C_sigfpe_flow_service.Make (Entropy)
  module SigILLFlow = C_sigill_flow_service.Make (Entropy)
  module ThreadedFlow = C_threaded_implicit_flow_service.Make (Entropy)
  module SyscallFlow = C_syscall_error_flow_service.Make (Entropy)
  module EncodeData = C_encode_data_service.Make (Entropy)
  module Merge = C_merge_functions_service.Make (Entropy)
  module Outline = C_outline_service.Make (Entropy)
  module Inline = C_inline_service.Make (Entropy)
  module CallFlatten = C_call_graph_flatten_service.Make (Entropy)
  module BogusCalls = C_bogus_calls_service.Make (Entropy)
  module RenameSymbols = C_rename_symbols_service.Make (Entropy)
  module StripDirectives = C_strip_directives_service.Make (Entropy)
  module AntiDebug = C_anti_debug_service.Make (Entropy)
  module AntiDisasm = C_anti_disassembly_service.Make (Entropy)
  module SelfChecksum = C_self_checksum_service.Make (Entropy)
  module TimingCheck = C_timing_check_service.Make (Entropy)
  module HookDetect = C_hook_detect_service.Make (Entropy)
  module ApiHash = C_api_hash_resolver_service.Make (Entropy)
  module EarlyConstructor = C_early_constructor_service.Make (Entropy)
  module RollingVKey = C_rolling_vkey_service.Make (Entropy)
  module VcpuScramble = C_vcpu_context_scramble_service.Make (Entropy)
  module EphemeralPayload = C_ephemeral_payload_service.Make (Entropy)
  module InstrSubst = C_instruction_subst_service.Make (Entropy)
  module InstrPermute = C_instruction_permute_service.Make (Entropy)
  module GhostCode = C_ghost_code_service.Make (Entropy)
  module LiveRangeSplit = C_live_range_split_service.Make (Entropy)
  module ConstUnfold = C_constant_unfold_service.Make (Entropy)
  module StackAliasing = C_stack_aliasing_service.Make (Entropy)
  module OpcodeEqualize = C_opcode_equalize_service.Make (Entropy)
  module AntiSlicing = C_anti_slicing_entanglement_service.Make (Entropy)
  module LUT = C_lut_arithmetic_service.Make (Entropy)
  module ArrayInterleave = C_array_interleave_service.Make (Entropy)
  module StructPermute = C_struct_permute_service.Make (Entropy)
  module PointerMask = C_pointer_masking_service.Make (Entropy)
  module Homomorphic = C_homomorphic_service.Make (Entropy)
  module Virtualize = C_visa_spec_service.Make (Entropy)
  module NestedVM = C_nested_vm_service.Make (Entropy)
  module SelfModVM = C_self_modifying_vm_service.Make (Entropy)
  module Jitify = C_jitify_service.Make (Entropy)
  module EGraphMBA = C_egraph_mba_service.Make (Entropy)
  module EHShadow = C_eh_shadowing_service.Make (Entropy)
  module VPCPath = C_vpc_path_invalidation_service.Make (Entropy)
  module LokiInvariants = C_loki_invariant_service.Make (Entropy)
  module MicroDispatcher = C_micro_dispatcher_service.Make (Entropy)
  module AntiVTIL = C_anti_vtil_aliasing_service.Make (Entropy)

  let run_passes (cil_file : GoblintCil.Cil.file) (config : c_pipeline_config) : GoblintCil.Cil.file =
    (match config.c_vm_profile with
     | Some p_str ->
         let prof = C_visa_profile_service.parse_profile p_str in
         C_visa_profile_service.set_active_profile prof
     | None -> ());
    let f = if config.enable_c_struct_permute then StructPermute.transform_file cil_file else cil_file in
    let f = if config.enable_c_inline then Inline.transform_file f else f in
    let f = if config.enable_c_merge then Merge.transform_file f else f in
    let f = if config.enable_c_outline then Outline.transform_file f else f in
    let f = if config.enable_c_bogus_calls then BogusCalls.transform_file f else f in
    let f = if config.enable_c_loop_unroll then LoopUnroll.transform_file f else f in
    let f = if config.enable_c_loop_fission then LoopFission.transform_file f else f in
    let f = if config.enable_c_irreducible_loop then IrreducibleLoop.transform_file f else f in
    let f = if config.enable_c_loop_to_recursion then LoopToRecursion.transform_file f else f in
    let f = if config.enable_c_array_interleave then ArrayInterleave.transform_file f else f in
    let f = if config.enable_c_pointer_mask then PointerMask.transform_file f else f in
    let f = if config.enable_c_encode_literals then EncodeLiterals.transform_file f else f in
    let f = if config.enable_c_encode_data then EncodeData.transform_file f else f in
    let f = if config.enable_c_homomorphic then Homomorphic.transform_file f else f in
    let f = if config.enable_c_float_mba then FloatMBA.transform_file f else f in
    let f = if config.enable_c_relational_morph then RelationalMorph.transform_file f else f in
    let f = if config.enable_c_instruction_subst then InstrSubst.transform_file f else f in
    let f = if config.enable_c_instruction_permute then InstrPermute.transform_file f else f in
    let f = if config.enable_c_constant_unfold then ConstUnfold.transform_file f else f in
    let f = LokiInvariants.transform_file ~global:config.enable_c_loki_invariants f in
    let f = if config.enable_c_polynomial_mba then PolyMBA.transform_file f else f in
    let f = if config.enable_c_lut then LUT.transform_file f else f in
    let f = EGraphMBA.transform_file ~depth:config.c_egraph_depth ~global:config.enable_c_egraph_mba f in
    let f = if config.enable_c_mba then MBA.transform_file f else f in
    let f = if config.enable_c_ghost_code then GhostCode.transform_file f else f in
    let f = if config.enable_c_live_range_split then LiveRangeSplit.transform_file f else f in
    let f = if config.enable_c_opcode_equalize then OpcodeEqualize.transform_file f else f in
    let f = if config.enable_c_anti_slicing then AntiSlicing.transform_file f else f in
    let f = if config.enable_c_opaque then Opaque.transform_file f else f in
    let f = if config.enable_c_dynamic_opaque then DynOpaque.transform_file f else f in
    let f = if config.enable_c_diophantine then Diophantine.transform_file f else f in
    let f = if config.enable_c_bogus_cf then BogusCF.transform_file f else f in
    let f = if config.enable_c_implicit_flow then ImplicitFlow.transform_file f else f in
    let f = if config.enable_c_sigfpe_flow then SigFPEFlow.transform_file f else f in
    let f = if config.enable_c_sigill_flow then SigILLFlow.transform_file f else f in
    let f = if config.enable_c_threaded_flow then ThreadedFlow.transform_file f else f in
    let f = if config.enable_c_syscall_flow then SyscallFlow.transform_file f else f in
    let f = if config.enable_c_call_flatten then CallFlatten.transform_file f else f in
    let f = if config.enable_c_indirect_jump then IndirectJump.transform_file f else f in
    let f = if config.enable_c_anti_vtil then AntiVTIL.transform_file ~global:true f else f in
    let f = if config.enable_c_micro_dispatcher then MicroDispatcher.transform_file ~global:true f else f in
    let f = if config.enable_c_virtualize then Virtualize.transform_file f else f in
    let f = if config.enable_c_nested_vm then NestedVM.transform_file f else f in
    let f = if config.enable_c_self_mod_vm then SelfModVM.transform_file f else f in
    let f = if config.enable_c_rolling_vkey then RollingVKey.transform_file f else f in
    let f = if config.enable_c_vcpu_scramble then VcpuScramble.transform_file f else f in
    let f = VPCPath.transform_file ~global:config.enable_c_vcpu_scramble f in
    let f = if config.enable_c_stack_aliasing then StackAliasing.transform_file f else f in
    let f = if config.enable_c_ephemeral_payload then EphemeralPayload.transform_file f else f in
    let f = if config.enable_c_jitify then Jitify.transform_file f else f in
    let f = EHShadow.transform_file ~global:config.enable_c_eh_shadow f in
    let f = if config.enable_c_anti_debug then AntiDebug.transform_file f else f in
    let f = if config.enable_c_anti_disasm then AntiDisasm.transform_file f else f in
    let f = if config.enable_c_self_checksum then SelfChecksum.transform_file f else f in
    let f = if config.enable_c_timing_check then TimingCheck.transform_file f else f in
    let f = if config.enable_c_hook_detect then HookDetect.transform_file f else f in
    let f = if config.enable_c_api_hash then ApiHash.transform_file f else f in
    let f = if config.enable_c_early_constructor then EarlyConstructor.transform_file f else f in
    let f = if config.enable_c_flattening then Flattening.transform_file f else f in
    let f = if config.enable_c_decentralized_disp then DecentDisp.transform_file f else f in
    let f = if config.enable_c_basic_block_split then BBSplit.transform_file f else f in
    let f = if config.enable_c_rename_symbols then RenameSymbols.transform_file f else f in
    let f = if config.enable_c_strip_directives then StripDirectives.transform_file f else f in
    f

  let obfuscate_c_string (source_code : string) (config : c_pipeline_config) : string =
    let cil_file = C_Port.parse_string source_code in
    let processed_file = run_passes cil_file config in
    C_Port.emit_to_string processed_file

  let obfuscate_c_file (in_path : string) (out_path : string) (config : c_pipeline_config) : unit =
    let cil_file = C_Port.parse_file in_path in
    let processed_file = run_passes cil_file config in
    C_Port.emit_to_file out_path processed_file
end
