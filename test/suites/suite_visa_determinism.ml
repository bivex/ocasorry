open Vectis_lib
open Helpers

let run () =
  Printf.printf "\n--- [Suite 62] Seeded Synthesis Determinism, Entropy & Guard Tests ---\n%!";

  let module Synth = Synthesize_isa_usecase.Make (System_entropy_adapter.Adapter) in

  let tmp_a = Filename.temp_file "det_a_" "" in
  let tmp_b = Filename.temp_file "det_b_" "" in
  let tmp_c = Filename.temp_file "det_c_" "" in
  (try Sys.remove tmp_a with _ -> ());
  (try Sys.remove tmp_b with _ -> ());
  (try Sys.remove tmp_c with _ -> ());
  Unix.mkdir tmp_a 0o755;
  Unix.mkdir tmp_b 0o755;
  Unix.mkdir tmp_c 0o755;

  (* 1. Determinism: Seed 42 x 2 -> Byte-identical JSON & Sail *)
  System_entropy_adapter.Adapter.seed 42;
  Synth.synthesize_4vcpu ~name:"vISA_Det_42" ~out_dir:tmp_a ();

  System_entropy_adapter.Adapter.seed 42;
  Synth.synthesize_4vcpu ~name:"vISA_Det_42" ~out_dir:tmp_b ();

  let read_file path =
    let ic = open_in_bin path in
    let len = in_channel_length ic in
    let s = really_input_string ic len in
    close_in ic;
    s
  in

  let files = [ "vcpu1_visa.json"; "vcpu1_visa.sail"; "vcpu2_nested_vm.json"; "vcpu3_rolling_vkey.json" ] in
  List.iter
    (fun f ->
      let content_a = read_file (Filename.concat tmp_a f) in
      let content_b = read_file (Filename.concat tmp_b f) in
      assert_bool (Printf.sprintf "Deterministic output for %s on seed 42" f) (content_a = content_b))
    files;

  (* 2. Divergence: Seed 43 -> Differs from Seed 42 *)
  System_entropy_adapter.Adapter.seed 43;
  Synth.synthesize_4vcpu ~name:"vISA_Det_43" ~out_dir:tmp_c ();

  let content_c = read_file (Filename.concat tmp_c "vcpu1_visa.json") in
  let content_a = read_file (Filename.concat tmp_a "vcpu1_visa.json") in
  assert_bool "Seed 42 and Seed 43 produce distinct vISA JSON specs" (content_a <> content_c);

  (* 3. Layout Diversity across 50 seeds *)
  let module S = C_isa_synthesizer_service.Make(System_entropy_adapter.Adapter) in
  let distinct_vd_shifts = Hashtbl.create 8 in
  let valid_count = ref 0 in
  for s = 1 to 50 do
    System_entropy_adapter.Adapter.seed s;
    let (spec, json_str, _) = S.generate_random_visa () in
    let parsed = C_visa_spec_service.VisaSpec.from_json_string json_str in
    C_visa_spec_service.VisaSpec.validate_layout parsed.layout;
    Hashtbl.replace distinct_vd_shifts spec.layout.vd_shift true;
    incr valid_count
  done;

  assert_bool "All 50 seeded syntheses validated successfully" (!valid_count = 50);
  let num_shifts = Hashtbl.length distinct_vd_shifts in
  assert_bool (Printf.sprintf ">= 3 distinct vd_shifts across 50 seeds (found %d)" num_shifts) (num_shifts >= 3);

  (* 4. Guard test: Non-visa JSON spec must raise Invalid_argument *)
  let nested_json = read_file (Filename.concat tmp_a "vcpu2_nested_vm.json") in
  let guard_triggered =
    try
      ignore (C_visa_spec_service.VisaSpec.from_json_string nested_json);
      false
    with Invalid_argument _ -> true
  in
  assert_bool "Non-vISA spec correctly rejected with Invalid_argument" guard_triggered;

  (* Cleanup *)
  let clean_dir dir =
    try
      let fs = Sys.readdir dir in
      Array.iter (fun f -> Sys.remove (Filename.concat dir f)) fs;
      Unix.rmdir dir
    with _ -> ()
  in
  clean_dir tmp_a;
  clean_dir tmp_b;
  clean_dir tmp_c
