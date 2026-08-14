open Cfg

(** Outbound port for machine code binary encoders *)
module type S = sig
  val architecture_name : string
  val encode_block : BasicBlock.t -> bytes
  val encode_cfg : CFG.t -> (bytes, string) result
end
