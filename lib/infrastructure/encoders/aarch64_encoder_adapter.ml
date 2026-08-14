open Cfg

(** Infrastructure Adapter: AArch64 (ARM64) Machine Code Encoder *)
module Adapter : Encoder_port.S = struct
  let architecture_name = "aarch64"

  let encode_block (b : BasicBlock.t) : bytes =
    Arm64_branch_resolver.resolve_and_emit (CFG.create ~entry:b.id ~blocks:[ b ])

  let encode_cfg (cfg : CFG.t) : (bytes, string) result =
    Ok (Arm64_branch_resolver.resolve_and_emit cfg)
end
