open GoblintCil.Cil

(** Domain Service: Granular Function Annotation Inspector
    Parses and verifies GCC/Clang __attribute__((annotate("..."))) directives
    on functions to enable fine-grained, per-function obfuscation & VM routing.
    Supports comma-separated and semicolon-separated multi-pass declarations:
    e.g., __attribute__((annotate("ocasorry:cff, poly_mba, relational_morph, anti_debug")))
*)
module AnnotationHelper = struct
  let clean_token (raw : string) : string =
    let s = String.trim (String.lowercase_ascii raw) in
    if String.starts_with ~prefix:"ocasorry:" s then
      String.sub s 9 (String.length s - 9)
    else if String.starts_with ~prefix:"ocasorry_" s then
      String.sub s 9 (String.length s - 9)
    else s

  let split_tokens (raw_str : string) : string list =
    let raw_list = String.split_on_char ',' raw_str in
    List.concat_map
      (fun item ->
        let sub_list = String.split_on_char ';' item in
        List.map clean_token sub_list)
      raw_list
    |> List.filter (fun s -> s <> "")

  let get_annotations (fd : fundec) : string list =
    let type_attrs =
      match fd.svar.vtype with
      | TFun (ret_ty, _, _, f_attrs) -> f_attrs @ (typeAttrs ret_ty)
      | other -> typeAttrs other
    in
    let all_attrs = fd.svar.vattr @ type_attrs in
    List.filter_map
      (function
        | Attr (("annotate" | "__annotate__"), [AStr s]) -> Some s
        | Attr (("annotate" | "__annotate__"), [ACons (s, _)]) -> Some s
        | _ -> None)
      all_attrs

  let get_tokens (fd : fundec) : string list =
    let raw_annotations = get_annotations fd in
    List.concat_map split_tokens raw_annotations

  let has_annotation (fd : fundec) (target : string) : bool =
    let target_clean = clean_token target in
    let tokens = get_tokens fd in
    List.exists
      (fun t ->
        t = target_clean
        || String.starts_with ~prefix:(target_clean ^ ":") t
        || String.starts_with ~prefix:(target_clean ^ "_") t)
      tokens

  let has_any_vm_annotation (fd : fundec) : bool =
    let tokens = get_tokens fd in
    List.exists
      (fun t ->
        List.exists
          (fun vm_tag ->
            t = vm_tag
            || String.starts_with ~prefix:(vm_tag ^ ":") t
            || String.starts_with ~prefix:(vm_tag ^ "_") t)
          [ "virtualize"; "visa"; "vector_vm";
            "nested_vm"; "nested";
            "rolling_vkey"; "rolling_key";
            "self_mod_vm"; "self_modifying";
            "ephemeral"; "ephemeral_jit";
            "jitify"; "jit" ])
      tokens

  let has_custom_annotations (fd : fundec) : bool =
    get_tokens fd <> []

  let should_skip_all (fd : fundec) : bool =
    has_annotation fd "no_obf"
    || has_annotation fd "no_obfuscation"
    || has_annotation fd "skip"

  let should_apply_pass (fd : fundec) (pass_tag : string) : bool =
    if should_skip_all fd then false
    else if has_custom_annotations fd then has_annotation fd pass_tag
    else true
end
