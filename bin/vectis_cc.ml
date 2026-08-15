open Vectis_lib

module CilSourceObfuscator = Obfuscate_c_source_usecase.Make
    (System_entropy_adapter.Adapter)
    (Goblint_cil_adapter.Adapter)

let underlying_cc =
  try Sys.getenv "VECTIS_CC" with Not_found -> "clang"

let is_verbose =
  try Sys.getenv "VECTIS_VERBOSE" = "1" with Not_found -> false

let () =
  let raw_args = List.tl (Array.to_list Sys.argv) in

  if raw_args = [] || List.mem "--version" raw_args || List.mem "-v" raw_args then (
    Printf.printf "Vectis C Compiler Wrapper (vectis-cc) v1.0.0\n";
    Printf.printf "  Underlying compiler: %s\n" underlying_cc;
    Printf.printf "  Obfuscation engine: OCaml + Goblint-CIL\n";
    if raw_args = [] then exit 0
  );

  let enable_mba = ref true in
  let enable_poly_mba = ref false in
  let enable_float_mba = ref false in
  let enable_cff = ref true in
  let enable_opaque = ref true in
  let enable_dyn_opaque = ref false in
  let enable_diophantine = ref false in
  let enable_bcf = ref false in
  let enable_bb_split = ref false in
  let enable_decentralized_disp = ref false in
  let enable_relational_morph = ref false in
  let enable_irreducible_loop = ref false in
  let enable_unroll = ref false in
  let enable_fission = ref false in
  let enable_loop_to_rec = ref false in
  let enable_indirect = ref false in
  let enable_literals = ref true in
  let enable_split = ref true in
  let enable_implicit = ref false in
  let enable_sigfpe = ref false in
  let enable_sigill = ref false in
  let enable_threaded = ref false in
  let enable_syscall = ref false in
  let enable_merge = ref false in
  let enable_outline = ref false in
  let enable_inline = ref false in
  let enable_call_flatten = ref false in
  let enable_bogus_calls = ref false in
  let enable_rename = ref false in
  let enable_strip = ref false in
  let enable_anti_debug = ref false in
  let enable_anti_disasm = ref false in
  let enable_self_checksum = ref false in
  let enable_timing_check = ref false in
  let enable_hook_detect = ref false in
  let enable_api_hash = ref false in
  let enable_early_constructor = ref false in
  let enable_rolling_vkey = ref false in
  let enable_vcpu_scramble = ref false in
  let enable_ephemeral_payload = ref false in
  let enable_instruction_subst = ref false in
  let enable_instruction_permute = ref false in
  let enable_ghost_code = ref false in
  let enable_live_range_split = ref false in
  let enable_constant_unfold = ref false in
  let enable_stack_aliasing = ref false in
  let enable_opcode_equalize = ref false in
  let enable_anti_slicing = ref false in
  let enable_lut = ref false in
  let enable_interleave = ref false in
  let enable_permute_struct = ref false in
  let enable_pointer_mask = ref false in
  let enable_homomorphic = ref false in
  let enable_virtualize = ref false in
  let enable_nested_vm = ref false in
  let enable_self_mod_vm = ref false in
  let enable_jitify = ref false in
  let disable_all = ref false in

  let compiler_args = ref [] in
  let temp_files = ref [] in

  List.iter
    (fun arg ->
      match arg with
      | "--vectis-disable" -> disable_all := true
      | "--vectis-no-mba" -> enable_mba := false
      | "--vectis-poly-mba" -> enable_poly_mba := true
      | "--vectis-float-mba" -> enable_float_mba := true
      | "--vectis-no-cff" -> enable_cff := false
      | "--vectis-no-opaque" -> enable_opaque := false
      | "--vectis-dyn-opaque" -> enable_dyn_opaque := true
      | "--vectis-diophantine" -> enable_diophantine := true
      | "--vectis-bcf" -> enable_bcf := true
      | "--vectis-split-bb" -> enable_bb_split := true
      | "--vectis-decentralized-disp" -> enable_decentralized_disp := true
      | "--vectis-relational-morph" -> enable_relational_morph := true
      | "--vectis-irreducible-loop" -> enable_irreducible_loop := true
      | "--vectis-unroll" -> enable_unroll := true
      | "--vectis-fission" -> enable_fission := true
      | "--vectis-loop-to-rec" -> enable_loop_to_rec := true
      | "--vectis-indirect" -> enable_indirect := true
      | "--vectis-lut" -> enable_lut := true
      | "--vectis-interleave" -> enable_interleave := true
      | "--vectis-permute-struct" -> enable_permute_struct := true
      | "--vectis-pointer-mask" -> enable_pointer_mask := true
      | "--vectis-homomorphic" -> enable_homomorphic := true
      | "--vectis-virtualize" -> enable_virtualize := true
      | "--vectis-nested-vm" -> enable_nested_vm := true
      | "--vectis-self-mod-vm" -> enable_self_mod_vm := true
      | "--vectis-rolling-vkey" -> enable_rolling_vkey := true
      | "--vectis-vcpu-scramble" -> enable_vcpu_scramble := true
      | "--vectis-ephemeral" -> enable_ephemeral_payload := true
      | "--vectis-subst" -> enable_instruction_subst := true
      | "--vectis-permute-instr" -> enable_instruction_permute := true
      | "--vectis-ghost" -> enable_ghost_code := true
      | "--vectis-live-range" -> enable_live_range_split := true
      | "--vectis-unfold-const" -> enable_constant_unfold := true
      | "--vectis-stack-alias" -> enable_stack_aliasing := true
      | "--vectis-equalize-opcodes" -> enable_opcode_equalize := true
      | "--vectis-anti-slicing" -> enable_anti_slicing := true
      | "--vectis-jitify" -> enable_jitify := true
      | "--vectis-no-literals" -> enable_literals := false
      | "--vectis-no-split" -> enable_split := false
      | "--vectis-implicit" -> enable_implicit := true
      | "--vectis-sigfpe" -> enable_sigfpe := true
      | "--vectis-sigill" -> enable_sigill := true
      | "--vectis-threaded" -> enable_threaded := true
      | "--vectis-syscall" -> enable_syscall := true
      | "--vectis-merge" -> enable_merge := true
      | "--vectis-outline" -> enable_outline := true
      | "--vectis-inline" -> enable_inline := true
      | "--vectis-call-flatten" -> enable_call_flatten := true
      | "--vectis-bogus-calls" -> enable_bogus_calls := true
      | "--vectis-rename" -> enable_rename := true
      | "--vectis-strip" -> enable_strip := true
      | "--vectis-anti-debug" -> enable_anti_debug := true
      | "--vectis-anti-disasm" -> enable_anti_disasm := true
      | "--vectis-self-checksum" -> enable_self_checksum := true
      | "--vectis-timing-check" -> enable_timing_check := true
      | "--vectis-hook-detect" -> enable_hook_detect := true
      | "--vectis-api-hash" -> enable_api_hash := true
      | "--vectis-constructor" -> enable_early_constructor := true
      | arg_str when String.starts_with ~prefix:"--vectis-visa-spec=" arg_str ->
          let spec_path = String.sub arg_str 21 (String.length arg_str - 21) in
          ignore (C_visa_spec_service.VisaSpec.load_from_file spec_path)
      | _ -> (
          if Filename.check_suffix arg ".c" && not !disable_all && Sys.file_exists arg then (
            let tmp_c = Filename.temp_file "vectis_obf_" ".c" in
            temp_files := tmp_c :: !temp_files;
            let config : Obfuscate_c_source_usecase.c_pipeline_config = {
              enable_c_mba = !enable_mba;
              enable_c_polynomial_mba = !enable_poly_mba;
              enable_c_float_mba = !enable_float_mba;
              enable_c_egraph_mba = false;
              c_egraph_depth = 3;
              enable_c_eh_shadow = false;
              enable_c_loki_invariants = false;
              enable_c_micro_dispatcher = false;
              enable_c_anti_vtil = false;
              enable_c_opaque = !enable_opaque;
              enable_c_dynamic_opaque = !enable_dyn_opaque;
              enable_c_diophantine = !enable_diophantine;
              enable_c_bogus_cf = !enable_bcf;
              enable_c_basic_block_split = !enable_bb_split;
              enable_c_decentralized_disp = !enable_decentralized_disp;
              enable_c_relational_morph = !enable_relational_morph;
              enable_c_irreducible_loop = !enable_irreducible_loop;
              enable_c_loop_unroll = !enable_unroll;
              enable_c_loop_fission = !enable_fission;
              enable_c_loop_to_recursion = !enable_loop_to_rec;
              enable_c_indirect_jump = !enable_indirect;
              enable_c_flattening = !enable_cff;
              enable_c_encode_literals = !enable_literals;
              enable_c_implicit_flow = !enable_implicit;
              enable_c_sigfpe_flow = !enable_sigfpe;
              enable_c_sigill_flow = !enable_sigill;
              enable_c_threaded_flow = !enable_threaded;
              enable_c_syscall_flow = !enable_syscall;
              enable_c_encode_data = !enable_split;
              enable_c_merge = !enable_merge;
              enable_c_outline = !enable_outline;
              enable_c_inline = !enable_inline;
              enable_c_call_flatten = !enable_call_flatten;
              enable_c_bogus_calls = !enable_bogus_calls;
              enable_c_rename_symbols = !enable_rename;
              enable_c_strip_directives = !enable_strip;
              enable_c_anti_debug = !enable_anti_debug;
              enable_c_anti_disasm = !enable_anti_disasm;
              enable_c_self_checksum = !enable_self_checksum;
              enable_c_timing_check = !enable_timing_check;
              enable_c_hook_detect = !enable_hook_detect;
              enable_c_api_hash = !enable_api_hash;
              enable_c_early_constructor = !enable_early_constructor;
              enable_c_rolling_vkey = !enable_rolling_vkey;
              enable_c_vcpu_scramble = !enable_vcpu_scramble;
              enable_c_ephemeral_payload = !enable_ephemeral_payload;
              enable_c_instruction_subst = !enable_instruction_subst;
              enable_c_instruction_permute = !enable_instruction_permute;
              enable_c_ghost_code = !enable_ghost_code;
              enable_c_live_range_split = !enable_live_range_split;
              enable_c_constant_unfold = !enable_constant_unfold;
              enable_c_stack_aliasing = !enable_stack_aliasing;
              enable_c_opcode_equalize = !enable_opcode_equalize;
              enable_c_anti_slicing = !enable_anti_slicing;
              enable_c_lut = !enable_lut;
              enable_c_array_interleave = !enable_interleave;
              enable_c_struct_permute = !enable_permute_struct;
              enable_c_pointer_mask = !enable_pointer_mask;
              enable_c_homomorphic = !enable_homomorphic;
              enable_c_virtualize = !enable_virtualize;
              enable_c_nested_vm = !enable_nested_vm;
              enable_c_self_mod_vm = !enable_self_mod_vm;
              enable_c_jitify = !enable_jitify;
              c_vm_profile = None;
            } in
            if is_verbose then
              Printf.eprintf "[vectis-cc] Obfuscating source: %s -> %s\n%!" arg tmp_c;
            (try
               CilSourceObfuscator.obfuscate_c_file arg tmp_c config;
               compiler_args := !compiler_args @ [ tmp_c ]
             with exn ->
               if is_verbose then
                 Printf.eprintf "[vectis-cc] Warning: CIL parsing failed (%s), passing original source\n%!"
                   (Printexc.to_string exn);
               compiler_args := !compiler_args @ [ arg ])
          ) else (
            compiler_args := !compiler_args @ [ arg ]
          )))
    raw_args;

  let cmd =
    String.concat " " (underlying_cc :: List.map Filename.quote !compiler_args)
  in
  if is_verbose then
    Printf.eprintf "[vectis-cc] Running: %s\n%!" cmd;

  let ret_code = Sys.command cmd in

  (* Clean up temporary files *)
  List.iter (fun f -> try Sys.remove f with _ -> ()) !temp_files;

  exit ret_code
