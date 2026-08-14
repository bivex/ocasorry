open GoblintCil.Cil
open GoblintCil.Frontc

module Adapter : C_source_port.S = struct
  let init_once =
    let initialized = ref false in
    fun () ->
      if not !initialized then (
        initCIL ();
        initialized := true
      )

  let parse_file (path : string) : file =
    init_once ();
    parse path ()

  let parse_string (c_code : string) : file =
    init_once ();
    let tmp_path = Filename.temp_file "ocasorry_" ".c" in
    let oc = open_out tmp_path in
    output_string oc c_code;
    close_out oc;
    let res =
      try parse tmp_path ()
      with exn ->
        (try Sys.remove tmp_path with _ -> ());
        raise exn
    in
    (try Sys.remove tmp_path with _ -> ());
    res

  let filter_builtins (f : file) : file =
    let non_builtins =
      List.filter
        (function
          | GVarDecl (v, _) when String.starts_with ~prefix:"__builtin_" v.vname
                              || String.starts_with ~prefix:"__atomic_" v.vname
                              || String.starts_with ~prefix:"__sync_" v.vname -> false
          | _ -> true)
        f.globals
    in
    { f with globals = non_builtins }

  let emit_to_string (f : file) : string =
    let filtered_file = filter_builtins f in
    let tmp_path = Filename.temp_file "ocasorry_out_" ".c" in
    let oc = open_out tmp_path in
    dumpFile defaultCilPrinter oc "" filtered_file;
    close_out oc;
    let ic = open_in tmp_path in
    let len = in_channel_length ic in
    let content = really_input_string ic len in
    close_in ic;
    (try Sys.remove tmp_path with _ -> ());
    content

  let emit_to_file (path : string) (f : file) : unit =
    let filtered_file = filter_builtins f in
    let oc = open_out path in
    dumpFile defaultCilPrinter oc "" filtered_file;
    close_out oc
end
