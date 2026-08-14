type c_pipeline_config = {
  enable_c_mba : bool;
  enable_c_opaque : bool;
  enable_c_flattening : bool;
  enable_c_encode_literals : bool;
  enable_c_implicit_flow : bool;
  enable_c_encode_data : bool;
}

let default_c_config = {
  enable_c_mba = true;
  enable_c_opaque = true;
  enable_c_flattening = true;
  enable_c_encode_literals = true;
  enable_c_implicit_flow = false;
  enable_c_encode_data = true;
}

module Make (Entropy : Entropy_port.S) (C_Port : C_source_port.S) = struct
  module MBA = C_mba_service.Make (Entropy)
  module Opaque = C_opaque_service.Make (Entropy)
  module Flattening = C_flattening_service.Make (Entropy)
  module EncodeLiterals = C_encode_literals_service.Make (Entropy)
  module ImplicitFlow = C_implicit_flow_service.Make (Entropy)
  module EncodeData = C_encode_data_service.Make (Entropy)

  let run_passes (cil_file : GoblintCil.Cil.file) (config : c_pipeline_config) : GoblintCil.Cil.file =
    let f = if config.enable_c_encode_literals then EncodeLiterals.transform_file cil_file else cil_file in
    let f = if config.enable_c_encode_data then EncodeData.transform_file f else f in
    let f = if config.enable_c_mba then MBA.transform_file f else f in
    let f = if config.enable_c_opaque then Opaque.transform_file f else f in
    let f = if config.enable_c_implicit_flow then ImplicitFlow.transform_file f else f in
    let f = if config.enable_c_flattening then Flattening.transform_file f else f in
    f

  let obfuscate_c_string (source_code : string) (config : c_pipeline_config) : string =
    let cil_file = C_Port.parse_string source_code in
    let processed_file = run_passes cil_file config in
    C_Port.emit_to_string processed_file

  let obfuscate_c_file (in_path : string) (out_path : string) (config : c_pipeline_config) : unit =
    let cil_file = C_Port.parse_file in_path in
    let processed_file = run_passes cil_file config in
    C_Port.emit_to_file out_path processed_file
end
