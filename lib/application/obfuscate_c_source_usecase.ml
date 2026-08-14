type c_pipeline_config = {
  enable_c_mba : bool;
  enable_c_opaque : bool;
  enable_c_flattening : bool;
}

let default_c_config = {
  enable_c_mba = true;
  enable_c_opaque = true;
  enable_c_flattening = true;
}

module Make (Entropy : Entropy_port.S) (C_Port : C_source_port.S) = struct
  module MBA = C_mba_service.Make (Entropy)
  module Opaque = C_opaque_service.Make (Entropy)
  module Flattening = C_flattening_service.Make (Entropy)

  let obfuscate_c_string (source_code : string) (config : c_pipeline_config) : string =
    let cil_file = C_Port.parse_string source_code in
    let _ = if config.enable_c_mba then MBA.transform_file cil_file else cil_file in
    let _ = if config.enable_c_opaque then Opaque.transform_file cil_file else cil_file in
    let _ = if config.enable_c_flattening then Flattening.transform_file cil_file else cil_file in
    C_Port.emit_to_string cil_file

  let obfuscate_c_file (in_path : string) (out_path : string) (config : c_pipeline_config) : unit =
    let cil_file = C_Port.parse_file in_path in
    let _ = if config.enable_c_mba then MBA.transform_file cil_file else cil_file in
    let _ = if config.enable_c_opaque then Opaque.transform_file cil_file else cil_file in
    let _ = if config.enable_c_flattening then Flattening.transform_file cil_file else cil_file in
    C_Port.emit_to_file out_path cil_file
end
