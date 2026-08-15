open Ocasorry_lib

(** CLI Entrypoint: OcaSorry Formal Multi-VCPU Sail & JSON Architecture Synthesizer
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

  let speclist = [
    ("-o", Arg.Set_string output_json, "Path to output JSON ISA specification");
    ("--output-json", Arg.Set_string output_json, "Path to output JSON ISA specification");
    ("-s", Arg.Set_string output_sail, "Path to output formal Sail specification (.sail)");
    ("--output-sail", Arg.Set_string output_sail, "Path to output formal Sail specification (.sail)");
    ("--vcpu", Arg.Set_string vcpu_mode, "Target VCPU tier: visa, nested_vm, rolling_vkey, ephemeral, all, 8vcpu (default: all)");
    ("--output-dir", Arg.Set_string output_dir, "Output directory to write all Sail and JSON specs");
    ("--name", Arg.Set_string custom_name, "Custom ISA architecture name");
    ("--seed", Arg.Set_int seed_val, "Deterministic random seed integer");
  ] in

  let usage_msg = "Usage: ocasorry-synth [options]\nNative Multi-VCPU & Formal Sail Architecture Synthesizer" in
  Arg.parse speclist (fun _ -> ()) usage_msg;

  if !seed_val >= 0 then Random.init !seed_val
  else Random.self_init ();

  let name_opt = if !custom_name <> "" then Some !custom_name else None in
  let sail_opt = if !output_sail <> "" then Some !output_sail else None in

  match !vcpu_mode with
  | "8vcpu" ->
      let out_d = if !output_dir <> "" then !output_dir else "." in
      SynthApp.synthesize_8vcpu ~out_dir:out_d ()
  | "all" ->
      let out_d = if !output_dir <> "" then !output_dir else "." in
      SynthApp.synthesize_4vcpu ?name:name_opt ~out_dir:out_d ()
  | single_mode ->
      if !output_dir <> "" then (
        let out_j = Filename.concat !output_dir (!vcpu_mode ^ ".json") in
        let out_s = Filename.concat !output_dir (!vcpu_mode ^ ".sail") in
        SynthApp.synthesize_single ~vcpu:single_mode ~out_json:out_j ~out_sail:out_s ?name:name_opt ()
      ) else (
        SynthApp.synthesize_single ~vcpu:single_mode ~out_json:!output_json ?out_sail:sail_opt ?name:name_opt ()
      )
