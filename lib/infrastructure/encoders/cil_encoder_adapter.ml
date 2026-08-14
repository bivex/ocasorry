open Cfg

(** Infrastructure Adapter: ECMA-335 CIL Bytecode Encoder *)
module Adapter : Encoder_port.S = struct
  let architecture_name = "cil_ecma335"

  let encode_block (b : BasicBlock.t) : bytes =
    Cil_branch_resolver.resolve_and_emit (CFG.create ~entry:b.id ~blocks:[ b ])

  let encode_cfg (cfg : CFG.t) : (bytes, string) result =
    Ok (Cil_branch_resolver.resolve_and_emit cfg)
end
