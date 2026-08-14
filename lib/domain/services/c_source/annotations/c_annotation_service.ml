open GoblintCil.Cil

(** Domain Service: Granular Function Annotation Inspector
    Parses and verifies GCC/Clang __attribute__((annotate("..."))) directives
    on functions to enable fine-grained, per-function obfuscation & VM routing.
*)
module AnnotationHelper = struct
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

  let has_annotation (fd : fundec) (target : string) : bool =
    let target_lower = String.lowercase_ascii target in
    List.exists
      (fun a ->
        let a_lower = String.lowercase_ascii a in
        a_lower = target_lower
        || a_lower = "ocasorry:" ^ target_lower
        || a_lower = "ocasorry_" ^ target_lower)
      (get_annotations fd)

  let has_any_vm_annotation (fd : fundec) : bool =
    List.exists (fun tag -> has_annotation fd tag)
      [ "virtualize"; "visa"; "vector_vm";
        "nested_vm"; "nested";
        "rolling_vkey"; "rolling_key";
        "self_mod_vm"; "self_modifying";
        "ephemeral"; "ephemeral_jit";
        "jitify"; "jit" ]

  let should_skip_all (fd : fundec) : bool =
    has_annotation fd "no_obf"
    || has_annotation fd "no_obfuscation"
    || has_annotation fd "skip"
end
