type c_pipeline_config = {
  enable_c_mba : bool;
  enable_c_polynomial_mba : bool;
  enable_c_opaque : bool;
  enable_c_dynamic_opaque : bool;
  enable_c_bogus_cf : bool;
  enable_c_loop_unroll : bool;
  enable_c_loop_fission : bool;
  enable_c_indirect_jump : bool;
  enable_c_flattening : bool;
  enable_c_encode_literals : bool;
  enable_c_implicit_flow : bool;
  enable_c_encode_data : bool;
  enable_c_merge : bool;
  enable_c_outline : bool;
  enable_c_lut : bool;
  enable_c_array_interleave : bool;
  enable_c_struct_permute : bool;
  enable_c_pointer_mask : bool;
  enable_c_homomorphic : bool;
}

let default_c_config = {
  enable_c_mba = true;
  enable_c_polynomial_mba = false;
  enable_c_opaque = true;
  enable_c_dynamic_opaque = false;
  enable_c_bogus_cf = false;
  enable_c_loop_unroll = false;
  enable_c_loop_fission = false;
  enable_c_indirect_jump = false;
  enable_c_flattening = true;
  enable_c_encode_literals = true;
  enable_c_implicit_flow = false;
  enable_c_encode_data = true;
  enable_c_merge = false;
  enable_c_outline = false;
  enable_c_lut = false;
  enable_c_array_interleave = false;
  enable_c_struct_permute = false;
  enable_c_pointer_mask = false;
  enable_c_homomorphic = false;
}

module Make (Entropy : Entropy_port.S) (C_Port : C_source_port.S) = struct
  module MBA = C_mba_service.Make (Entropy)
  module PolyMBA = C_polynomial_mba_service.Make (Entropy)
  module Opaque = C_opaque_service.Make (Entropy)
  module DynOpaque = C_dynamic_opaque_service.Make (Entropy)
  module BogusCF = C_bogus_control_flow_service.Make (Entropy)
  module LoopUnroll = C_loop_unroll_service.Make (Entropy)
  module LoopFission = C_loop_fission_service.Make (Entropy)
  module IndirectJump = C_indirect_jump_service.Make (Entropy)
  module Flattening = C_flattening_service.Make (Entropy)
  module EncodeLiterals = C_encode_literals_service.Make (Entropy)
  module ImplicitFlow = C_implicit_flow_service.Make (Entropy)
  module EncodeData = C_encode_data_service.Make (Entropy)
  module Merge = C_merge_functions_service.Make (Entropy)
  module Outline = C_outline_service.Make (Entropy)
  module LUT = C_lut_arithmetic_service.Make (Entropy)
  module ArrayInterleave = C_array_interleave_service.Make (Entropy)
  module StructPermute = C_struct_permute_service.Make (Entropy)
  module PointerMask = C_pointer_masking_service.Make (Entropy)
  module Homomorphic = C_homomorphic_service.Make (Entropy)

  let run_passes (cil_file : GoblintCil.Cil.file) (config : c_pipeline_config) : GoblintCil.Cil.file =
    let f = if config.enable_c_struct_permute then StructPermute.transform_file cil_file else cil_file in
    let f = if config.enable_c_merge then Merge.transform_file f else f in
    let f = if config.enable_c_outline then Outline.transform_file f else f in
    let f = if config.enable_c_loop_unroll then LoopUnroll.transform_file f else f in
    let f = if config.enable_c_loop_fission then LoopFission.transform_file f else f in
    let f = if config.enable_c_array_interleave then ArrayInterleave.transform_file f else f in
    let f = if config.enable_c_pointer_mask then PointerMask.transform_file f else f in
    let f = if config.enable_c_encode_literals then EncodeLiterals.transform_file f else f in
    let f = if config.enable_c_encode_data then EncodeData.transform_file f else f in
    let f = if config.enable_c_homomorphic then Homomorphic.transform_file f else f in
    let f = if config.enable_c_polynomial_mba then PolyMBA.transform_file f else f in
    let f = if config.enable_c_lut then LUT.transform_file f else f in
    let f = if config.enable_c_mba then MBA.transform_file f else f in
    let f = if config.enable_c_opaque then Opaque.transform_file f else f in
    let f = if config.enable_c_dynamic_opaque then DynOpaque.transform_file f else f in
    let f = if config.enable_c_bogus_cf then BogusCF.transform_file f else f in
    let f = if config.enable_c_implicit_flow then ImplicitFlow.transform_file f else f in
    let f = if config.enable_c_indirect_jump then IndirectJump.transform_file f else f in
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
