open Domain.Cfg
open Domain.Ports

type pipeline_config = {
  enable_mba : bool;
  enable_opaque : bool;
  enable_flattening : bool;
}

let default_config = {
  enable_mba = true;
  enable_opaque = true;
  enable_flattening = true;
}

module Make (Entropy : Entropy_port.S) = struct
  module MBA = Domain.Services.Mba_service.Make (Entropy)
  module Opaque = Domain.Services.Opaque_predicate_service.Make (Entropy)
  module Flattening = Domain.Services.Flattening_service.Make (Entropy)

  let run (cfg : CFG.t) (config : pipeline_config) : CFG.t =
    let cfg = if config.enable_mba then MBA.transform_cfg cfg else cfg in
    let cfg = if config.enable_opaque then Opaque.transform_cfg cfg else cfg in
    let cfg = if config.enable_flattening then Flattening.transform_cfg cfg else cfg in
    cfg
end
