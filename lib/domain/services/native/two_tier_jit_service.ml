open Ast
open Cfg

type two_tier_payload = {
  tier1_bytes : bytes;
  tier2_encrypted_bytes : bytes;
  tier2_plain_bytes : bytes;
  encryption_key : int;
}

module Make (Entropy : Entropy_port.S) (Encoder : Encoder_port.S) = struct
  module MBA = Mba_service.Make (Entropy)
  module Flattening = Flattening_service.Make (Entropy)
  module Opaque = Opaque_predicate_service.Make (Entropy)

  let prepare_payload (target_cfg : CFG.t) (config : Obfuscation_pipeline.pipeline_config) : two_tier_payload =
    (* 1. Obfuscate Tier 2 (Inner target algorithm) *)
    let cfg = if config.enable_mba then MBA.transform_cfg target_cfg else target_cfg in
    let cfg = if config.enable_opaque then Opaque.transform_cfg cfg else cfg in
    let cfg = if config.enable_flattening then Flattening.transform_cfg cfg else cfg in

    let tier2_plain_bytes =
      match Encoder.encode_cfg cfg with
      | Ok b -> b
      | Error err -> failwith ("Failed to encode Tier 2 CFG: " ^ err)
    in

    (* 2. Generate dynamic session encryption key & encrypt Tier 2 *)
    let key = 1 + Entropy.next_int ~max:254 in
    let len2 = Bytes.length tier2_plain_bytes in
    let tier2_enc_bytes = Bytes.create len2 in
    for i = 0 to len2 - 1 do
      let b = Char.code (Bytes.get tier2_plain_bytes i) in
      Bytes.set tier2_enc_bytes i (Char.chr (b lxor key))
    done;

    (* 3. Synthesize Tier 1 (Outer Dispatcher / Hardware Trap Generator)
          Uses BRK #0x42 (0xD4200840) to trigger Implicit Hardware Signal Flow *)
    let trap_block =
      BasicBlock.create
        ~id:"tier1_entry"
        ~instructions:[
          Raw32 0xD4200840l; (* BRK #0x42 -> SIGTRAP hardware fault *)
          Ret None;
        ]
    in
    let tier1_cfg = CFG.create ~entry:"tier1_entry" ~blocks:[ trap_block ] in

    let tier1_bytes =
      match Encoder.encode_cfg tier1_cfg with
      | Ok b -> b
      | Error err -> failwith ("Failed to encode Tier 1 CFG: " ^ err)
    in

    {
      tier1_bytes;
      tier2_encrypted_bytes = tier2_enc_bytes;
      tier2_plain_bytes;
      encryption_key = key;
    }
end
