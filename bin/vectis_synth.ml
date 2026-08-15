open Vectis_lib

(** CLI Entrypoint: Vectis Formal Multi-VCPU Sail & JSON Architecture Synthesizer
    Native OCaml replacement for tools/visa_synthesizer.py
*)

module SynthApp = Synthesize_isa_usecase.Make (System_entropy_adapter.Adapter)

let () =
  let output_json = ref "visa_spec.json" in
  let output_sail = ref "" in
  let vcpu_mode = ref "all" in
  let output_dir = ref "" in
  let custom_name = ref "" in
  let seed_val = ref (-1) in

  let gf_poly = ref (-1) in
  let rol_const = ref (-1) in
  let imm_bits = ref (-1) in
  let hash_bits = ref (-1) in
  let stack_depth = ref (-1) in
  let state_regs = ref (-1) in
  let key_bits = ref (-1) in
  let lcg_mult = ref (-1) in
  let lcg_delta_str = ref "" in
  let page_shift = ref (-1) in
  let wipe_passes = ref (-1) in
  let jit_regs = ref (-1) in

  let speclist = [
    ("-o", Arg.Set_string output_json, "Path to output JSON ISA specification");
    ("--output-json", Arg.Set_string output_json, "Path to output JSON ISA specification");
    ("-s", Arg.Set_string output_sail, "Path to output formal Sail specification (.sail)");
    ("--output-sail", Arg.Set_string output_sail, "Path to output formal Sail specification (.sail)");
    ("--vcpu", Arg.Set_string vcpu_mode, "Target VCPU tier: visa, nested_vm, rolling_vkey, ephemeral, all, 8vcpu (default: all)");
    ("--output-dir", Arg.Set_string output_dir, "Output directory to write all Sail and JSON specs");
    ("--name", Arg.Set_string custom_name, "Custom ISA architecture name");
    ("--seed", Arg.Set_int seed_val, "Deterministic random seed integer");
    ("--gf-poly", Arg.Set_int gf_poly, "Override GF(2^8) reduction polynomial (e.g. 0x1B, 0x8D)");
    ("--rol-const", Arg.Set_int rol_const, "Override bitwise rotation constant (1..15)");
    ("--imm-bits", Arg.Set_int imm_bits, "Override immediate bit width (12, 14, 16)");
    ("--hash-bits", Arg.Set_int hash_bits, "Override nested VM hash bits (32, 48, 64)");
    ("--stack-depth", Arg.Set_int stack_depth, "Override nested VM stack depth (4..16)");
    ("--state-regs", Arg.Set_int state_regs, "Override VM state register count (4..12)");
    ("--key-bits", Arg.Set_int key_bits, "Override rolling key bits (32, 48, 64)");
    ("--lcg-mult", Arg.Set_int lcg_mult, "Override rolling LCG multiplier (17..65535, odd)");
    ("--lcg-delta", Arg.Set_string lcg_delta_str, "Override rolling LCG delta constant (e.g. 0x9E3779B9)");
    ("--page-shift", Arg.Set_int page_shift, "Override ephemeral JIT page shift (12..15)");
    ("--wipe-passes", Arg.Set_int wipe_passes, "Override ephemeral memory wipe passes (1..6)");
    ("--jit-regs", Arg.Set_int jit_regs, "Override ephemeral JIT register count (4..7)");
  ] in

  let usage_msg = "Usage: vectis-synth [options]\nNative Multi-VCPU & Formal Sail Architecture Synthesizer" in
  Arg.parse speclist (fun _ -> ()) usage_msg;

  (* Seed the adapter the synthesis path actually uses (System_entropy_adapter
     holds its own PRNG state; the global Random module is never consumed). *)
  if !seed_val >= 0 then System_entropy_adapter.Adapter.seed !seed_val;

  let opt_int r = if !r >= 0 then Some !r else None in
  let opt_int64 s =
    if !s <> "" then (
      try Some (Int64.of_string !s)
      with _ -> None
    ) else None
  in
  let params : C_isa_sail_templates.synth_params = {
    gf_poly = opt_int gf_poly;
    rol_const = opt_int rol_const;
    imm_bits = opt_int imm_bits;
    hash_bits = opt_int hash_bits;
    stack_depth = opt_int stack_depth;
    state_regs = opt_int state_regs;
    key_bits = opt_int key_bits;
    lcg_mult = opt_int lcg_mult;
    lcg_delta = opt_int64 lcg_delta_str;
    page_shift = opt_int page_shift;
    wipe_passes = opt_int wipe_passes;
    jit_regs = opt_int jit_regs;
  } in

  let name_opt = if !custom_name <> "" then Some !custom_name else None in
  let sail_opt = if !output_sail <> "" then Some !output_sail else None in

  match !vcpu_mode with
  | "8vcpu" ->
      let out_d = if !output_dir <> "" then !output_dir else "." in
      SynthApp.synthesize_8vcpu ~params ~out_dir:out_d ()
  | "all" ->
      let out_d = if !output_dir <> "" then !output_dir else "." in
      SynthApp.synthesize_4vcpu ?name:name_opt ~params ~out_dir:out_d ()
  | single_mode ->
      if !output_dir <> "" then (
        let out_j = Filename.concat !output_dir (!vcpu_mode ^ ".json") in
        let out_s = Filename.concat !output_dir (!vcpu_mode ^ ".sail") in
        SynthApp.synthesize_single ~vcpu:single_mode ~out_json:out_j ~out_sail:out_s ?name:name_opt ~params ()
      ) else (
        SynthApp.synthesize_single ~vcpu:single_mode ~out_json:!output_json ?out_sail:sail_opt ?name:name_opt ~params ()
      )
