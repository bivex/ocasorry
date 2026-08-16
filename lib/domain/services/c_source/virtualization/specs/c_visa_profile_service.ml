(** Domain Service: Virtual Machine Hardening Profiles & Synthetic Poly-Trap Matrix
    Provides configuration and code generation for scaling internal VM code size from
    compact (64 KB) up to Titan 512 KB and Colossus 1 MB+ tiers.
*)

type vm_profile_kind =
  | Profile_Compact
  | Profile_Standard
  | Profile_Hardened_128k
  | Profile_Fortress_256k
  | Profile_Titan_512k
  | Profile_Colossus_1m
  | Profile_Singularity_Alpha
  | Profile_Singularity_Beta
  | Profile_Singularity_Gamma
  | Profile_Singularity_Omega

type vm_profile_config = {
  kind : vm_profile_kind;
  name : string;
  dispatch_size : int;
  mba_depth : int;
  decoy_density : int;
  lut_count : int;
  poly_aliases : int;
}

let profile_compact = {
  kind = Profile_Compact;
  name = "compact";
  dispatch_size = 64;
  mba_depth = 1;
  decoy_density = 2;
  lut_count = 0;
  poly_aliases = 1;
}

let profile_standard = {
  kind = Profile_Standard;
  name = "standard";
  dispatch_size = 64;
  mba_depth = 2;
  decoy_density = 5;
  lut_count = 1;
  poly_aliases = 2;
}

let profile_hardened_128k = {
  kind = Profile_Hardened_128k;
  name = "hardened-128k";
  dispatch_size = 128;
  mba_depth = 2;
  decoy_density = 10;
  lut_count = 4;
  poly_aliases = 4;
}

let profile_fortress_256k = {
  kind = Profile_Fortress_256k;
  name = "fortress-256k";
  dispatch_size = 256;
  mba_depth = 3;
  decoy_density = 25;
  lut_count = 8;
  poly_aliases = 6;
}

let profile_titan_512k = {
  kind = Profile_Titan_512k;
  name = "titan-512k";
  dispatch_size = 512;
  mba_depth = 4;
  decoy_density = 50;
  lut_count = 16;
  poly_aliases = 8;
}

let profile_colossus_1m = {
  kind = Profile_Colossus_1m;
  name = "colossus-1m";
  dispatch_size = 512;
  mba_depth = 4;
  decoy_density = 100;
  lut_count = 32;
  poly_aliases = 16;
}

let profile_singularity_alpha = {
  kind = Profile_Singularity_Alpha;
  name = "singularity-alpha";
  dispatch_size = 1024;
  mba_depth = 4;
  decoy_density = 120;
  lut_count = 48;
  poly_aliases = 24;
}

let profile_singularity_beta = {
  kind = Profile_Singularity_Beta;
  name = "singularity-beta";
  dispatch_size = 1024;
  mba_depth = 4;
  decoy_density = 160;
  lut_count = 56;
  poly_aliases = 28;
}

let profile_singularity_gamma = {
  kind = Profile_Singularity_Gamma;
  name = "singularity-gamma";
  dispatch_size = 1024;
  mba_depth = 4;
  decoy_density = 180;
  lut_count = 64;
  poly_aliases = 32;
}

let profile_singularity_omega = {
  kind = Profile_Singularity_Omega;
  name = "singularity-omega";
  dispatch_size = 1024;
  mba_depth = 4;
  decoy_density = 200;
  lut_count = 64;
  poly_aliases = 32;
}

let parse_profile (s : string) : vm_profile_config =
  match String.lowercase_ascii s with
  | "compact" | "small" -> profile_compact
  | "standard" | "default" -> profile_standard
  | "hardened" | "128k" | "hardened-128k" -> profile_hardened_128k
  | "fortress" | "256k" | "fortress-256k" -> profile_fortress_256k
  | "titan" | "512k" | "titan-512k" | "extreme" -> profile_titan_512k
  | "colossus" | "1m" | "colossus-1m" | "monster" -> profile_colossus_1m
  | "singularity-alpha" | "singularity-2m" | "alpha" -> profile_singularity_alpha
  | "singularity-beta" | "singularity-3m" | "beta" -> profile_singularity_beta
  | "singularity-gamma" | "singularity-4m" | "gamma" -> profile_singularity_gamma
  | "singularity" | "5m" | "singularity-5m" | "singularity-omega" | "omega" -> profile_singularity_omega
  | _ -> profile_standard

let active_profile = ref profile_standard

let set_active_profile (p : vm_profile_config) : unit =
  active_profile := p

let get_active_profile () : vm_profile_config =
  !active_profile

(** Generate S-Box substitution LUT tables in C .rodata *)
let generate_sbox_luts (lut_count : int) : string =
  if lut_count <= 0 then ""
  else
    let luts = ref [] in
    for i = 0 to lut_count - 1 do
      let table_bytes = Array.init 256 (fun j ->
        let s = (j * 0x5A + 0x1F + (i * 0x37)) land 0xFF in
        let s = ((s lsl 1) lor (s lsr 7)) land 0xFF in
        s lxor 0xA5
      ) in
      let byte_strs = Array.map (Printf.sprintf "0x%02X") table_bytes in
      let formatted = String.concat ", " (Array.to_list byte_strs) in
      luts := Printf.sprintf "static const unsigned char __vm_sbox_%d[256] = {\n    %s\n};\n" i formatted :: !luts
    done;
    String.concat "\n" (List.rev !luts)

(** Generate unique synthetic non-linear polynomial trap handlers *)
let generate_synthetic_trap_handlers ~(vs1 : string) ~(vs2 : string) ~(vd : string) ~(start_slot : int) ~(total_slots : int) ~(lut_count : int) : string * (int * string) list =
  if start_slot >= total_slots then ("", [])

  else
    let handlers = ref [] in
    let bindings = ref [] in
    for slot = start_slot to total_slots - 1 do
      let label = Printf.sprintf "__h_trap_%d" slot in
      bindings := (slot, label) :: !bindings;
      let c1 = (0x1000000 + (slot * 0x9E3779B9)) land 0xFFFFFFFF in
      let c2 = (0x2000000 + (slot * 0x517CC1B7)) land 0xFFFFFFFF in
      let k = (0x3000000 + (slot * 0x6C62272E)) land 0xFFFFFFFF in
      let sbox_mod = if lut_count > 0 then Printf.sprintf " ^ __vm_sbox_%d[__VREG_GET(%s) & 0xFF]" (slot mod lut_count) vd else "" in
      let h_code = Printf.sprintf {|
%s: {
    unsigned long long __a = __VREG_GET(%s) ^ 0x%XULL, __b = __VREG_GET(%s) + 0x%XULL;
    unsigned long long __x1 = (__a ^ __b) + ((__a & __b) << 1);
    unsigned long long __x2 = ((__a | __b) << 1) - (__a ^ __b);
    unsigned long long __al = __x1 & 0xFFFFFFFFULL, __ah = __x1 >> 32;
    unsigned long long __bl = __x2 & 0xFFFFFFFFULL, __bh = __x2 >> 32;
    unsigned long long __p0 = __al * __bl, __p2 = __ah * __bh;
    unsigned long long __p1 = (__al + __ah) * (__bl + __bh) - __p0 - __p2;
    unsigned long long __x3 = __p0 + ((__p1 ^ 0x%XULL) << 32);
    unsigned long long __x4 = (__x3 ^ (__x1 + __x2)) - ((~__x1 & __x2) << 1);
    __VREG_SET(%s, ((__x4 ^ 0x%XULL) + 0x%XULL)%s);
    __VISA_DISPATCH();
}
|} label vs1 c1 vs2 c2 k vd c1 c2 sbox_mod in
      handlers := h_code :: !handlers
    done;
    (String.concat "" (List.rev !handlers), List.rev !bindings)


let format_trap_bindings (bindings : (int * string) list) : string =
  if bindings = [] then ""
  else
    bindings
    |> List.map (fun (slot, label) -> Printf.sprintf "        [0x%X] = &&%s," slot label)
    |> String.concat "\n"
