open Ocasorry_lib

module CilSourceObfuscator = Obfuscate_c_source_usecase.Make
    (System_entropy_adapter.Adapter)
    (Goblint_cil_adapter.Adapter)

let underlying_cc =
  try Sys.getenv "OCASORRY_CC" with Not_found -> "clang"

let is_verbose =
  try Sys.getenv "OCASORRY_VERBOSE" = "1" with Not_found -> false

let () =
  let raw_args = List.tl (Array.to_list Sys.argv) in

  if raw_args = [] || List.mem "--version" raw_args || List.mem "-v" raw_args then (
    Printf.printf "OcaSorry C Compiler Wrapper (ocasorry-cc) v1.0.0\n";
    Printf.printf "  Underlying compiler: %s\n" underlying_cc;
    Printf.printf "  Obfuscation engine: OCaml + Goblint-CIL\n";
    if raw_args = [] then exit 0
  );

  let enable_mba = ref true in
  let enable_poly_mba = ref false in
  let enable_cff = ref true in
  let enable_opaque = ref true in
  let enable_dyn_opaque = ref false in
  let enable_bcf = ref false in
  let enable_unroll = ref false in
  let enable_fission = ref false in
  let enable_indirect = ref false in
  let enable_literals = ref true in
  let enable_split = ref true in
  let enable_implicit = ref false in
  let enable_sigfpe = ref false in
  let enable_sigill = ref false in
  let enable_threaded = ref false in
  let enable_syscall = ref false in
  let enable_merge = ref false in
  let enable_outline = ref false in
  let enable_inline = ref false in
  let enable_call_flatten = ref false in
  let enable_bogus_calls = ref false in
  let enable_lut = ref false in
  let enable_interleave = ref false in
  let enable_permute_struct = ref false in
  let enable_pointer_mask = ref false in
  let enable_homomorphic = ref false in
  let enable_virtualize = ref false in
  let enable_nested_vm = ref false in
  let enable_self_mod_vm = ref false in
  let enable_jitify = ref false in
  let disable_all = ref false in

  let compiler_args = ref [] in
  let temp_files = ref [] in

  List.iter
    (fun arg ->
      match arg with
      | "--ocasorry-disable" -> disable_all := true
      | "--ocasorry-no-mba" -> enable_mba := false
      | "--ocasorry-poly-mba" -> enable_poly_mba := true
      | "--ocasorry-no-cff" -> enable_cff := false
      | "--ocasorry-no-opaque" -> enable_opaque := false
      | "--ocasorry-dyn-opaque" -> enable_dyn_opaque := true
      | "--ocasorry-bcf" -> enable_bcf := true
      | "--ocasorry-unroll" -> enable_unroll := true
      | "--ocasorry-fission" -> enable_fission := true
      | "--ocasorry-indirect" -> enable_indirect := true
      | "--ocasorry-lut" -> enable_lut := true
      | "--ocasorry-interleave" -> enable_interleave := true
      | "--ocasorry-permute-struct" -> enable_permute_struct := true
      | "--ocasorry-pointer-mask" -> enable_pointer_mask := true
      | "--ocasorry-homomorphic" -> enable_homomorphic := true
      | "--ocasorry-virtualize" -> enable_virtualize := true
      | "--ocasorry-nested-vm" -> enable_nested_vm := true
      | "--ocasorry-self-mod-vm" -> enable_self_mod_vm := true
      | "--ocasorry-jitify" -> enable_jitify := true
      | "--ocasorry-no-literals" -> enable_literals := false
      | "--ocasorry-no-split" -> enable_split := false
      | "--ocasorry-implicit" -> enable_implicit := true
      | "--ocasorry-sigfpe" -> enable_sigfpe := true
      | "--ocasorry-sigill" -> enable_sigill := true
      | "--ocasorry-threaded" -> enable_threaded := true
      | "--ocasorry-syscall" -> enable_syscall := true
      | "--ocasorry-merge" -> enable_merge := true
      | "--ocasorry-outline" -> enable_outline := true
      | "--ocasorry-inline" -> enable_inline := true
      | "--ocasorry-call-flatten" -> enable_call_flatten := true
      | "--ocasorry-bogus-calls" -> enable_bogus_calls := true
      | _ -> (
          if Filename.check_suffix arg ".c" && not !disable_all && Sys.file_exists arg then (
            let tmp_c = Filename.temp_file "ocasorry_obf_" ".c" in
            temp_files := tmp_c :: !temp_files;
            let config : Obfuscate_c_source_usecase.c_pipeline_config = {
              enable_c_mba = !enable_mba;
              enable_c_polynomial_mba = !enable_poly_mba;
              enable_c_opaque = !enable_opaque;
              enable_c_dynamic_opaque = !enable_dyn_opaque;
              enable_c_bogus_cf = !enable_bcf;
              enable_c_loop_unroll = !enable_unroll;
              enable_c_loop_fission = !enable_fission;
              enable_c_indirect_jump = !enable_indirect;
              enable_c_flattening = !enable_cff;
              enable_c_encode_literals = !enable_literals;
              enable_c_implicit_flow = !enable_implicit;
              enable_c_sigfpe_flow = !enable_sigfpe;
              enable_c_sigill_flow = !enable_sigill;
              enable_c_threaded_flow = !enable_threaded;
              enable_c_syscall_flow = !enable_syscall;
              enable_c_encode_data = !enable_split;
              enable_c_merge = !enable_merge;
              enable_c_outline = !enable_outline;
              enable_c_inline = !enable_inline;
              enable_c_call_flatten = !enable_call_flatten;
              enable_c_bogus_calls = !enable_bogus_calls;
              enable_c_lut = !enable_lut;
              enable_c_array_interleave = !enable_interleave;
              enable_c_struct_permute = !enable_permute_struct;
              enable_c_pointer_mask = !enable_pointer_mask;
              enable_c_homomorphic = !enable_homomorphic;
              enable_c_virtualize = !enable_virtualize;
              enable_c_nested_vm = !enable_nested_vm;
              enable_c_self_mod_vm = !enable_self_mod_vm;
              enable_c_jitify = !enable_jitify;
            } in
            if is_verbose then
              Printf.eprintf "[ocasorry-cc] Obfuscating source: %s -> %s\n%!" arg tmp_c;
            (try
               CilSourceObfuscator.obfuscate_c_file arg tmp_c config;
               compiler_args := !compiler_args @ [ tmp_c ]
             with exn ->
               if is_verbose then
                 Printf.eprintf "[ocasorry-cc] Warning: CIL parsing failed (%s), passing original source\n%!"
                   (Printexc.to_string exn);
               compiler_args := !compiler_args @ [ arg ])
          ) else (
            compiler_args := !compiler_args @ [ arg ]
          )))
    raw_args;

  let cmd =
    String.concat " " (underlying_cc :: List.map Filename.quote !compiler_args)
  in
  if is_verbose then
    Printf.eprintf "[ocasorry-cc] Running: %s\n%!" cmd;

  let ret_code = Sys.command cmd in

  (* Clean up temporary files *)
  List.iter (fun f -> try Sys.remove f with _ -> ()) !temp_files;

  exit ret_code
