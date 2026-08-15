open Yojson.Basic.Util

(** Specification Types and JSON parser for random_vISA Virtual Processors *)
type visa_field_layout = {
  funct6_shift : int;
  funct6_mask : int;
  vm_shift : int;
  vs2_shift : int;
  vs1_shift : int;
  funct3_shift : int;
  vd_shift : int;
  opcode_val : int;
}

type visa_opcodes = {
  vadd_vv : int;
  vsub_vv : int;
  vmul_vv : int;
  vxor_vv : int;
  vand_vv : int;
  vor_vv  : int;
  vsll_vv : int;
  vsrl_vv : int;
  vli_vi  : int;
  vmv_vv  : int;
  vle8_v  : int;
  vse8_v  : int;
  vret_v  : int;
  vbge_vv : int;
  vj      : int;
}

type visa_abi = {
  in_regs : int list;
  out_reg : int;
}

type visa_spec = {
  isa_name : string;
  isa_version : string;
  word_bits : int;
  reg_count : int;
  pack_key : int64;
  delta_key : int64;
  layout : visa_field_layout;
  opcodes : visa_opcodes;
  abi : visa_abi;
}

let default_spec : visa_spec = {
  isa_name = "vISA_Standard_RISCV_Vector";
  isa_version = "1.0";
  word_bits = 32;
  reg_count = 16;
  pack_key = 0x5A5AA5A5L;
  delta_key = 0x1000193L;
  layout = {
    funct6_shift = 26;
    funct6_mask = 0x3F;
    vm_shift = 25;
    vs2_shift = 20;
    vs1_shift = 15;
    funct3_shift = 12;
    vd_shift = 7;
    opcode_val = 0x57;
  };
  opcodes = {
    vadd_vv = 0x00;
    vsub_vv = 0x01;
    vmul_vv = 0x02;
    vxor_vv = 0x03;
    vand_vv = 0x04;
    vor_vv  = 0x05;
    vsll_vv = 0x06;
    vsrl_vv = 0x07;
    vli_vi  = 0x08;
    vmv_vv  = 0x0D;
    vle8_v  = 0x0E;
    vse8_v  = 0x15;
    vret_v  = 0x0F;
    vbge_vv = 0x13;
    vj      = 0x14;
  };
  abi = {
    in_regs = [0; 1; 2; 3; 4; 5; 6; 7];
    out_reg = 0;
  };
}

let active_spec = ref default_spec

let set_active_spec (spec : visa_spec) : unit =
  active_spec := spec

let get_active_spec () : visa_spec =
  !active_spec

let to_str_def def = function
  | `String s -> s
  | _ -> def

let to_int_def def = function
  | `Int i -> i
  | _ -> def

let from_json_string (json_str : string) : visa_spec =
  let json = Yojson.Basic.from_string json_str in
  let isa_name = json |> member "isa_name" |> to_str_def "vISA_Custom" in
  let isa_version = json |> member "isa_version" |> to_str_def "1.0" in
  let word_bits = json |> member "word_bits" |> to_int_def 32 in
  let reg_count = json |> member "reg_count" |> to_int_def 16 in
  let pack_key =
    match json |> member "pack_key" with
    | `Int i -> Int64.of_int i
    | `String s -> Int64.of_string s
    | _ -> 0x5A5AA5A5L
  in
  let delta_key =
    match json |> member "delta_key" with
    | `Int i -> Int64.of_int i
    | `String s -> Int64.of_string s
    | _ -> 0x1000193L
  in
  let lay = json |> member "layout" in
  let layout = {
    funct6_shift = lay |> member "funct6_shift" |> to_int_def 26;
    funct6_mask  = lay |> member "funct6_mask" |> to_int_def 0x3F;
    vm_shift     = lay |> member "vm_shift" |> to_int_def 25;
    vs2_shift    = lay |> member "vs2_shift" |> to_int_def 20;
    vs1_shift    = lay |> member "vs1_shift" |> to_int_def 15;
    funct3_shift = lay |> member "funct3_shift" |> to_int_def 12;
    vd_shift     = lay |> member "vd_shift" |> to_int_def 7;
    opcode_val   = lay |> member "opcode_val" |> to_int_def 0x57;
  } in
  let op = json |> member "opcodes" in
  let opcodes = {
    vadd_vv = op |> member "vadd_vv" |> to_int_def 0x00;
    vsub_vv = op |> member "vsub_vv" |> to_int_def 0x01;
    vmul_vv = op |> member "vmul_vv" |> to_int_def 0x02;
    vxor_vv = op |> member "vxor_vv" |> to_int_def 0x03;
    vand_vv = op |> member "vand_vv" |> to_int_def 0x04;
    vor_vv  = op |> member "vor_vv"  |> to_int_def 0x05;
    vsll_vv = op |> member "vsll_vv" |> to_int_def 0x06;
    vsrl_vv = op |> member "vsrl_vv" |> to_int_def 0x07;
    vli_vi  = op |> member "vli_vi"  |> to_int_def 0x08;
    vmv_vv  = op |> member "vmv_vv"  |> to_int_def 0x0D;
    vle8_v  = op |> member "vle8_v"  |> to_int_def 0x0E;
    vse8_v  = op |> member "vse8_v"  |> to_int_def 0x15;
    vret_v  = op |> member "vret_v"  |> to_int_def 0x0F;
    vbge_vv = op |> member "vbge_vv" |> to_int_def 0x13;
    vj      = op |> member "vj"      |> to_int_def 0x14;
  } in
  let abi =
    match json |> member "abi" with
    | `Null -> { in_regs = [0; 1; 2; 3; 4; 5; 6; 7]; out_reg = 0 }
    | abi_obj ->
        let out_r = abi_obj |> member "out_reg" |> to_int_def 0 in
        let in_r =
          match abi_obj |> member "in_regs" with
          | `List items -> List.filter_map (function `Int x -> Some x | _ -> None) items
          | _ -> [0; 1; 2; 3; 4; 5; 6; 7]
        in
        { in_regs = (if in_r = [] then [0; 1; 2; 3] else in_r); out_reg = out_r }
  in
  {
    isa_name;
    isa_version;
    word_bits;
    reg_count;
    pack_key;
    delta_key;
    layout;
    opcodes;
    abi;
  }

let load_from_file (file_path : string) : visa_spec =
  let ic = open_in file_path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  let spec = from_json_string s in
  active_spec := spec;
  spec

let encode_inst (spec : visa_spec) ~funct6 ~vm ~vs2 ~vs1_or_imm ~funct3 ~vd =
  let l = spec.layout in
  let word =
    (((funct6 land l.funct6_mask) lsl l.funct6_shift) lor
     ((vm land 0x01) lsl l.vm_shift) lor
     ((vs2 land 0x1F) lsl l.vs2_shift) lor
     ((vs1_or_imm land 0x1F) lsl l.vs1_shift) lor
     ((funct3 land 0x07) lsl l.funct3_shift) lor
     ((vd land 0x1F) lsl l.vd_shift) lor
     (l.opcode_val land 0x7F)) land 0xFFFFFFFF
  in
  Int32.of_int word
