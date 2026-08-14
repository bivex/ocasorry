open Cfg

type two_tier_run_result = {
  tier1_bytes : bytes;
  tier2_encrypted_bytes : bytes;
  encryption_key : int;
  result_val : int64;
}

module Make (Entropy : Entropy_port.S) (Encoder : Encoder_port.S) = struct
  module Service = Two_tier_jit_service.Make (Entropy) (Encoder)

  let execute_two_tier_fn2 (target_cfg : CFG.t) (x0 : int64) (x1 : int64) (config : Obfuscation_pipeline.pipeline_config) : (two_tier_run_result, string) result =
    let payload = Service.prepare_payload target_cfg config in
    match Posix_mmap_adapter.run_two_tier_jit payload.tier1_bytes payload.tier2_encrypted_bytes payload.encryption_key x0 x1 with
    | Ok res ->
        Ok {
          tier1_bytes = payload.tier1_bytes;
          tier2_encrypted_bytes = payload.tier2_encrypted_bytes;
          encryption_key = payload.encryption_key;
          result_val = res;
        }
    | Error err -> Error err
end
