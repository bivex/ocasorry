open Vectis_lib
open Helpers

(** Suite: Per-Function Multi-ISA Fragmentation
    Loads a pool of vISA specs and verifies that functions without an
    explicit "visa:NAME" annotation are bound to DIFFERENT ISAs via the
    stable name hash (C_visa_spec.get_fragmented_spec), that explicit
    annotations still pin a named spec, and that a two-function program
    virtualized over the pool stays I/O-equivalent. *)

let run () =
  Printf.printf "\n--- [Suite] Multi-ISA Per-Function Fragmentation Tests ---\n%!";

  let tmp_dir = Filename.temp_file "multi_isa_" "" in
  (try Sys.remove tmp_dir with _ -> ());
  Unix.mkdir tmp_dir 0o755;

  (* 1. Synthesize two distinct visa fragments (deterministic seeds) *)
  System_entropy_adapter.Adapter.seed 9001;
  let module Synth = Synthesize_isa_usecase.Make (System_entropy_adapter.Adapter) in
  let spec_a = Filename.concat tmp_dir "frag_a.json" in
  let spec_b = Filename.concat tmp_dir "frag_b.json" in
  Synth.synthesize_single ~vcpu:"visa" ~out_json:spec_a ~name:"ML_Multi_ISA_A" ();
  Synth.synthesize_single ~vcpu:"visa" ~out_json:spec_b ~name:"ML_Multi_ISA_B" ();

  assert_bool "Fragment A spec exists" (Sys.file_exists spec_a);
  assert_bool "Fragment B spec exists" (Sys.file_exists spec_b);

  (* 2. Load both — registry now holds an ISA pool *)
  let a = C_visa_spec_service.VisaSpec.load_from_file spec_a in
  let b = C_visa_spec_service.VisaSpec.load_from_file spec_b in
  assert_bool "Fragments have distinct names" (a.isa_name <> b.isa_name);

  let pool = C_visa_spec_service.VisaSpec.list_specs () in
  assert_bool "ISA pool holds >= 2 specs" (List.length pool >= 2);

  (* 3. Explicit annotation still pins the named spec *)
  let pinned = C_visa_spec_service.VisaSpec.get_spec_for_annotation (Some "ML_Multi_ISA_B") in
  assert_bool "Explicit visa:NAME annotation pins the named spec"
    (pinned.isa_name = "ML_Multi_ISA_B");

  (* 4. Un-annotated functions fragment across the pool *)
  let assigned =
    List.init 16 (fun i ->
        C_visa_spec_service.VisaSpec.get_fragmented_spec (Printf.sprintf "fn_test_%d" i))
    |> List.map (fun (s : C_visa_spec_service.VisaSpec.visa_spec) -> s.isa_name)
    |> List.sort_uniq compare
  in
  assert_bool "Fragmentation distributes functions over >1 ISA"
    (List.length assigned > 1);

  (* 5. End-to-end: two plain-annotated functions virtualize over the pool *)
  let c_code = {|
extern int atoi(const char *nptr);
extern int printf(const char *format, ...);

__attribute__((annotate("vectis:visa")))
int frag_alpha(int a, int b) { return ((a + b) * 3 ^ 0x5A) + 11; }

__attribute__((annotate("vectis:visa")))
int frag_beta(int a, int b) { return (a * b) + (a ^ b) - 7; }

int main(int argc, char **argv) {
    int a = atoi(argv[1]);
    int b = atoi(argv[2]);
    printf("%d %d\n", frag_alpha(a, b), frag_beta(a, b));
    return 0;
}
|} in

  let c_config : Obfuscate_c_source_usecase.c_pipeline_config = {
    Obfuscate_c_source_usecase.default_c_config with
    enable_c_mba = false;
    enable_c_opaque = false;
    enable_c_flattening = false;
    enable_c_encode_literals = false;
    enable_c_encode_data = false;
    enable_c_virtualize = true;
  } in
  let obfuscated_c = CilSourceObfuscator.obfuscate_c_string c_code c_config in
  assert_bool "Bytecode tables generated for both functions"
    (let has name =
       try
         ignore (Str.search_forward (Str.regexp_string name) obfuscated_c 0);
         true
       with Not_found -> false
     in
     has "__visa_program_frag_alpha" && has "__visa_program_frag_beta");

  (* Both functions' VMs embedded — their dispatch layouts must differ when
     they landed on different fragments. Find the two vd/vs shift sets. *)
  let src_file = Filename.temp_file "multi_isa_" ".c" in
  let bin_file = Filename.temp_file "multi_isa_" ".bin" in
  let oc = open_out src_file in
  output_string oc obfuscated_c;
  close_out oc;

  assert_bool "Clang compilation of fragmented multi-ISA code succeeded"
    (Sys.command (Printf.sprintf "clang -w -O2 %s -o %s"
                    (Filename.quote src_file) (Filename.quote bin_file)) = 0);

  List.iter
    (fun (a, b) ->
      let expected_a = ((((a + b) * 3) lxor 0x5A) + 11) in
      let expected_b = ((a * b) + (a lxor b) - 7) in
      let ic = Unix.open_process_in
          (Printf.sprintf "%s %d %d" (Filename.quote bin_file) a b) in
      let out_line = input_line ic in
      ignore (Unix.close_process_in ic);
      let actual =
        match String.split_on_char ' ' (String.trim out_line) with
        | [ xa; xb ] -> (int_of_string xa, int_of_string xb)
        | _ -> (-1, -1)
      in
      assert_bool
        (Printf.sprintf "fragmented frag_alpha(%d,%d)==%d frag_beta==%d (got %d %d)"
           a b expected_a expected_b (fst actual) (snd actual))
        (actual = (expected_a, expected_b)))
    [ (5, 10); (0, 0); (13, 29); (100, 7) ];

  (* Restore default active spec for later suites *)
  C_visa_spec_service.VisaSpec.set_active_spec C_visa_spec_service.VisaSpec.default_spec;

  (try Sys.remove src_file with _ -> ());
  (try Sys.remove bin_file with _ -> ());
  (try
     Array.iter (fun f -> try Sys.remove (Filename.concat tmp_dir f) with _ -> ())
       (Sys.readdir tmp_dir);
     Unix.rmdir tmp_dir
   with _ -> ());

  Printf.printf "  [PASS] Multi-ISA fragmentation: pool, pinning, distribution, I/O equivalence\n%!"
