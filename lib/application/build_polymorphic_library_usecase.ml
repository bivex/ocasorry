(** Application Use Case: Build Polymorphic Shared Library (.dylib / .so / .dll / .a)
    Orchestrates end-to-end synthesis of unique per-build virtual architectures,
    AST obfuscation passes, and compilation into stripped native shared libraries with
    Standard C ABI (cdecl / AAPCS64) zero-wrapper interop.
*)

module Make
    (Entropy : Entropy_port.S)
    (C_Port : C_source_port.S) = struct

  module ObfApp = Obfuscate_c_source_usecase.Make (Entropy) (C_Port)
  module Synth = C_isa_synthesizer_service.Make (Entropy)

  type target_format =
    | SharedDylib
    | SharedSo
    | SharedDll
    | StaticArchive

  let detect_format (out_path : string) : target_format =
    if Filename.check_suffix out_path ".dylib" then SharedDylib
    else if Filename.check_suffix out_path ".so" then SharedSo
    else if Filename.check_suffix out_path ".dll" then SharedDll
    else if Filename.check_suffix out_path ".a" then StaticArchive
    else if Sys.os_type = "Unix" then (
      let uname_p = Unix.open_process_in "uname -s" in
      let s = input_line uname_p in
      close_in uname_p;
      if String.trim s = "Darwin" then SharedDylib else SharedSo
    ) else SharedDll

  let export_flags_needed_for_ld (syms : string list) : bool =
    syms <> [] && Sys.os_type = "Unix" &&
    (let uname_p = Unix.open_process_in "uname -s" in
     let s = input_line uname_p in
     close_in uname_p;
     String.trim s = "Darwin")

  let build_shared_library
      ?(compiler : string option)
      ?(export_symbols : string list = [])
      ~(input_c : string)
      ~(output_lib : string)
      ~(config : Obfuscate_c_source_usecase.c_pipeline_config)
      () : (string, string) result =

    let cc =
      match compiler with
      | Some c -> c
      | None ->
          (try Sys.getenv "CC" with Not_found ->
             try Sys.getenv "VECTIS_CC" with Not_found -> "clang")
    in

    let tmp_dir = Filename.temp_file "vectis_lib_" "" in
    (try Sys.remove tmp_dir with _ -> ());
    Unix.mkdir tmp_dir 0o755;

    let tmp_obf_c = Filename.concat tmp_dir "lib_obfuscated.c" in
    let tmp_isa_dir = Filename.concat tmp_dir "isas" in
    Unix.mkdir tmp_isa_dir 0o755;

    (* 1. Synthesize fresh randomized ISA specs for this build *)
    Synth.synthesize_4vcpu_cascade ~out_dir:tmp_isa_dir ();
    let visa_json = Filename.concat tmp_isa_dir "vcpu1_visa.json" in

    (* 2. Run AST Obfuscation & Virtualization pipeline *)
    let obf_result =
      try
        ignore (C_visa_spec_service.VisaSpec.load_from_file visa_json);
        ObfApp.obfuscate_c_file input_c tmp_obf_c config;
        Ok ()
      with exn ->
        Error (Printf.sprintf "Obfuscation pass failed: %s" (Printexc.to_string exn))
    in

    match obf_result with
    | Error msg ->
        (try ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmp_dir))) with _ -> ());
        Error msg
    | Ok () ->
        (* 3. Determine compiler flags based on target format *)
        let fmt = detect_format output_lib in
        let shared_flags =
          match fmt with
          | SharedDylib -> "-dynamiclib -fPIC -fvisibility=hidden"
          | SharedSo -> "-shared -fPIC -fvisibility=hidden"
          | SharedDll -> "-shared -fvisibility=hidden"
          | StaticArchive -> "-c -fPIC -fvisibility=hidden"
        in

        let export_flags =
          if export_flags_needed_for_ld export_symbols then
            List.map (fun sym -> Printf.sprintf "-Wl,-exported_symbol,_%s" sym) export_symbols
            |> String.concat " "
          else ""
        in

        let compile_cmd =
          Printf.sprintf "%s -O2 %s %s -o %s %s"
            cc shared_flags (Filename.quote tmp_obf_c) (Filename.quote output_lib) export_flags
        in

        let compile_res = Sys.command compile_cmd in
        if compile_res <> 0 then (
          (try ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmp_dir))) with _ -> ());
          Error (Printf.sprintf "Compilation failed with exit code %d (command: %s)" compile_res compile_cmd)
        ) else (
          (* 4. Strip non-exported symbols and sign on macOS *)
          (try
             if fmt = SharedDylib then (
               ignore (Sys.command (Printf.sprintf "strip -x %s 2>/dev/null" (Filename.quote output_lib)));
               ignore (Sys.command (Printf.sprintf "codesign -s - %s 2>/dev/null" (Filename.quote output_lib)))
             ) else if fmt = SharedSo then (
               ignore (Sys.command (Printf.sprintf "strip --strip-unneeded %s 2>/dev/null" (Filename.quote output_lib)))
             )
           with _ -> ());

          (* Clean up temp directory *)
          (try ignore (Sys.command (Printf.sprintf "rm -rf %s" (Filename.quote tmp_dir))) with _ -> ());
          Ok output_lib
        )
end
