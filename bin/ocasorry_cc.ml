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
  let enable_cff = ref true in
  let enable_opaque = ref true in
  let enable_literals = ref true in
  let enable_split = ref true in
  let enable_implicit = ref false in
  let disable_all = ref false in

  let compiler_args = ref [] in
  let temp_files = ref [] in

  List.iter
    (fun arg ->
      match arg with
      | "--ocasorry-disable" -> disable_all := true
      | "--ocasorry-no-mba" -> enable_mba := false
      | "--ocasorry-no-cff" -> enable_cff := false
      | "--ocasorry-no-opaque" -> enable_opaque := false
      | "--ocasorry-no-literals" -> enable_literals := false
      | "--ocasorry-no-split" -> enable_split := false
      | "--ocasorry-implicit" -> enable_implicit := true
      | _ -> (
          if Filename.check_suffix arg ".c" && not !disable_all && Sys.file_exists arg then (
            let tmp_c = Filename.temp_file "ocasorry_obf_" ".c" in
            temp_files := tmp_c :: !temp_files;
            let config : Obfuscate_c_source_usecase.c_pipeline_config = {
              enable_c_mba = !enable_mba;
              enable_c_opaque = !enable_opaque;
              enable_c_flattening = !enable_cff;
              enable_c_encode_literals = !enable_literals;
              enable_c_implicit_flow = !enable_implicit;
              enable_c_encode_data = !enable_split;
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
