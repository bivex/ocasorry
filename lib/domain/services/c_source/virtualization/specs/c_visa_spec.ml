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
  vadd_vv : int; vsub_vv : int; vmul_vv : int;
  vxor_vv : int; vand_vv : int; vor_vv  : int;
  vsll_vv : int; vsrl_vv : int; vli_vi  : int;
  vmv_vv  : int; vle8_v  : int; vse8_v  : int;
  vret_v  : int; vbge_vv : int; vj      : int;
  vadd_alt1 : int; vadd_alt2 : int;
  vsub_alt1 : int; vsub_alt2 : int;
  vxor_alt1 : int; vxor_alt2 : int;
  vand_alt1 : int; vor_alt1  : int;
  vmul_alt1 : int; vmv_alt1  : int; vli_alt1  : int;
  vjit_vv   : int; vjit_alt1 : int;
}

type visa_abi = { in_regs : int list; out_reg : int }

type visa_spec = {
  isa_name    : string;
  isa_version : string;
  word_bits   : int;
  reg_count   : int;
  pack_key    : int64;
  delta_key   : int64;
  layout      : visa_field_layout;
  opcodes     : visa_opcodes;
  abi         : visa_abi;
}

let default_spec : visa_spec = {
  isa_name = "vISA_Standard_RISCV_Vector";
  isa_version = "1.0"; word_bits = 32; reg_count = 16;
  pack_key = 0x5A5AA5A5L; delta_key = 0x1000193L;
  layout = {
    funct6_shift = 26; funct6_mask = 0x3F; vm_shift = 25;
    vs2_shift = 20; vs1_shift = 15; funct3_shift = 12;
    vd_shift = 7; opcode_val = 0x57;
  };
  opcodes = {
    vadd_vv = 0x00; vsub_vv = 0x01; vmul_vv = 0x02;
    vxor_vv = 0x03; vand_vv = 0x04; vor_vv  = 0x05;
    vsll_vv = 0x06; vsrl_vv = 0x07; vli_vi  = 0x08;
    vmv_vv  = 0x0D; vle8_v  = 0x0E; vse8_v  = 0x15;
    vret_v  = 0x0F; vbge_vv = 0x13; vj      = 0x14;
    vadd_alt1 = 0x18; vadd_alt2 = 0x19;
    vsub_alt1 = 0x1A; vsub_alt2 = 0x1B;
    vxor_alt1 = 0x1C; vxor_alt2 = 0x1D;
    vand_alt1 = 0x1E; vor_alt1  = 0x1F;
    vmul_alt1 = 0x20; vmv_alt1  = 0x21; vli_alt1  = 0x22;
    vjit_vv   = 0x23; vjit_alt1 = 0x24;
  };
  abi = { in_regs = [0; 1; 2; 3; 4; 5; 6; 7]; out_reg = 0 };
}

(** Multi-ISA Registry: named specs + active fallback.
    This is the fix for the global mutable active_spec race condition.
    Multiple specs can coexist; functions bind to a named ISA via annotation. *)
let registry : (string, visa_spec) Hashtbl.t = Hashtbl.create 8
let active_spec = ref default_spec

let register_spec (name : string) (spec : visa_spec) : unit =
  Hashtbl.replace registry name spec;
  (* First registered spec becomes the active default *)
  if Hashtbl.length registry = 1 then active_spec := spec

let find_spec (name : string) : visa_spec option =
  match Hashtbl.find_opt registry name with
  | Some s -> Some s
  | None ->
      let lower = String.lowercase_ascii name in
      Hashtbl.fold (fun k v acc ->
        if acc <> None then acc
        else if String.lowercase_ascii k = lower then Some v
        else None
      ) registry None

let set_active_spec (spec : visa_spec) : unit =
  active_spec := spec;
  Hashtbl.replace registry spec.isa_name spec

(** Get spec by annotation value "visa:MyISA_Name" or fall back to active *)
let get_spec_for_annotation (ann : string option) : visa_spec =
  match ann with
  | None -> !active_spec
  | Some name ->
      (match find_spec name with
       | Some s -> s
       | None   -> !active_spec)

let get_active_spec () : visa_spec = !active_spec

(** Layout soundness invariants.
    - opcode occupies [6:0] (encoded unshifted, `land 0x7F`) and funct6 is a
      6-bit selector at [31:26] (dispatch masks with `funct6_mask`, extraction
      into an unsigned char, trap slots start at 64).
    - funct3 must sit directly above vd (funct3_shift = vd_shift + 5): the two
      form the fused contiguous 8-bit branch-target field.
    - The fused pair (8), vm (1), vs2 (5) and vs1 (5) must tile [25:7] exactly
      with no overlap: the leftover 19-bit window is the unconditional-jump
      target and must stay contiguous. *)
exception Invalid_layout of string

let validate_layout (l : visa_field_layout) : unit =
  if l.funct6_shift <> 26 || l.funct6_mask <> 0x3F then
    raise (Invalid_layout "funct6 must be a 6-bit field at [31..26] (mask 0x3F)");
  if l.opcode_val < 0 || l.opcode_val > 0x7F then
    raise (Invalid_layout "opcode_val must fit the unshifted 7-bit field [6..0]");
  if l.vd_shift < 7 then
    raise (Invalid_layout "vd_shift must be >= 7 (opcode owns [6..0])");
  if l.funct3_shift <> l.vd_shift + 5 then
    raise (Invalid_layout "funct3_shift must equal vd_shift + 5 (fused branch-target pair)");
  let cover = Array.make 19 0 in
  List.iter
    (fun (s, w) ->
      if s < 7 || s + w > 26 then
        raise (Invalid_layout (Printf.sprintf "field at shift %d (width %d) escapes [25..7]" s w));
      for b = s to s + w - 1 do
        cover.(b - 7) <- cover.(b - 7) + 1
      done)
    [ (l.vd_shift, 8); (l.vm_shift, 1); (l.vs2_shift, 5); (l.vs1_shift, 5) ];
  Array.iteri
    (fun i c ->
      if c <> 1 then
        raise (Invalid_layout (Printf.sprintf "bit %d covered %dx — fields must tile [25..7] exactly" (i + 7) c)))
    cover

let to_str_def def = function `String s -> s | _ -> def
let to_int_def def = function `Int i    -> i | _ -> def

let from_json_string (json_str : string) : visa_spec =
  let json = Yojson.Basic.from_string json_str in
  (* Reject non-vISA specs (nested_vm / rolling_vkey / ephemeral JSONs) instead
     of silently registering a default-spec under their name. Absent vcpu_type
     means a legacy / hand-written spec — accepted for backward compat. *)
  (match json |> member "vcpu_type" with
   | `String t when t <> "visa" ->
       invalid_arg
         (Printf.sprintf
            "C_visa_spec.from_json_string: not a vISA spec (vcpu_type=%S) — refusing to fall back to defaults"
            t)
   | _ -> ());
  let isa_name    = json |> member "isa_name"    |> to_str_def "vISA_Custom" in
  let isa_version = json |> member "isa_version" |> to_str_def "1.0" in
  let word_bits   = json |> member "word_bits"   |> to_int_def 32 in
  let reg_count   = json |> member "reg_count"   |> to_int_def 16 in
  let pack_key = match json |> member "pack_key" with
    | `Int i    -> Int64.of_int i
    | `String s -> Int64.of_string s
    | _         -> 0x5A5AA5A5L in
  let delta_key = match json |> member "delta_key" with
    | `Int i    -> Int64.of_int i
    | `String s -> Int64.of_string s
    | _         -> 0x1000193L in
  let lay = json |> member "layout" in
  let layout = {
    funct6_shift = lay |> member "funct6_shift" |> to_int_def 26;
    funct6_mask  = lay |> member "funct6_mask"  |> to_int_def 0x3F;
    vm_shift     = lay |> member "vm_shift"     |> to_int_def 25;
    vs2_shift    = lay |> member "vs2_shift"    |> to_int_def 20;
    vs1_shift    = lay |> member "vs1_shift"    |> to_int_def 15;
    funct3_shift = lay |> member "funct3_shift" |> to_int_def 12;
    vd_shift     = lay |> member "vd_shift"     |> to_int_def 7;
    opcode_val   = lay |> member "opcode_val"   |> to_int_def 0x57;
  } in
  validate_layout layout;
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
    vadd_alt1 = op |> member "vadd_alt1" |> to_int_def 0x18;
    vadd_alt2 = op |> member "vadd_alt2" |> to_int_def 0x19;
    vsub_alt1 = op |> member "vsub_alt1" |> to_int_def 0x1A;
    vsub_alt2 = op |> member "vsub_alt2" |> to_int_def 0x1B;
    vxor_alt1 = op |> member "vxor_alt1" |> to_int_def 0x1C;
    vxor_alt2 = op |> member "vxor_alt2" |> to_int_def 0x1D;
    vand_alt1 = op |> member "vand_alt1" |> to_int_def 0x1E;
    vor_alt1  = op |> member "vor_alt1"  |> to_int_def 0x1F;
    vmul_alt1 = op |> member "vmul_alt1" |> to_int_def 0x20;
    vmv_alt1  = op |> member "vmv_alt1"  |> to_int_def 0x21;
    vli_alt1  = op |> member "vli_alt1"  |> to_int_def 0x22;
    vjit_vv   = op |> member "vjit_vv"   |> to_int_def 0x23;
    vjit_alt1 = op |> member "vjit_alt1" |> to_int_def 0x24;
  } in
  let abi = match json |> member "abi" with
    | `Null -> { in_regs = [0; 1; 2; 3; 4; 5; 6; 7]; out_reg = 0 }
    | abi_obj ->
        let out_r = abi_obj |> member "out_reg" |> to_int_def 0 in
        let in_r = match abi_obj |> member "in_regs" with
          | `List items ->
              List.filter_map (function `Int x -> Some x | _ -> None) items
          | _ -> [0; 1; 2; 3; 4; 5; 6; 7]
        in
        { in_regs = (if in_r = [] then [0;1;2;3] else in_r); out_reg = out_r }
  in
  { isa_name; isa_version; word_bits; reg_count;
    pack_key; delta_key; layout; opcodes; abi }

(** Load a spec from file and register it by name.
    Does NOT overwrite active_spec if other specs already exist — allows
    loading multiple ISAs without last-write-wins race. *)
let load_from_file (file_path : string) : visa_spec =
  let ic = open_in file_path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  let spec = from_json_string s in
  register_spec spec.isa_name spec;
  (* Always update active_spec to the latest loaded for backward compat *)
  active_spec := spec;
  spec

(** Load multiple ISA files at once. First file = active default. *)
let load_many (paths : string list) : visa_spec list =
  List.mapi (fun i path ->
    let spec = load_from_file path in
    if i = 0 then active_spec := spec;
    spec
  ) paths

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
