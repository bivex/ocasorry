(** Application Use Case: Multi-VCPU & Formal Sail ISA Architecture Synthesis
    Orchestrates the synthesis of multi-tier virtual machine ISAs, formal Sail specifications,
    and JSON schemas without relying on external Python runtimes.
*)

module Make (Entropy : Entropy_port.S) = struct
  module Synth = C_isa_synthesizer_service.Make (Entropy)

  let synthesize_4vcpu ?(name : string option) ~(out_dir : string) () : unit =
    Synth.synthesize_4vcpu_cascade ?name ~out_dir ()

  let synthesize_8vcpu ~(out_dir : string) () : unit =
    Synth.synthesize_8vcpu_cascade ~out_dir ()

  let synthesize_single ~(vcpu : string) ~(out_json : string) ?(out_sail : string option) ?(name : string option) () : unit =
    Synth.synthesize_single ~vcpu ~out_json ?out_sail ?name ()
end
