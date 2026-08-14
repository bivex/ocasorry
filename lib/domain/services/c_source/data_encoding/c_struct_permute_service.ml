open GoblintCil.Cil

(** Domain Service: Struct Field Permutation & Padding for CIL AST
    Reorders fields in structure definitions (CompInfo) and injects random padding bytes,
    preventing automated structure layout recovery in Ghidra / IDA Pro.
*)
module Make (Entropy : Entropy_port.S) = struct
  let pad_counter = ref 0

  let permute_and_pad_struct (comp : compinfo) : unit =
    if comp.cstruct && List.length comp.cfields >= 1 then (
      incr pad_counter;
      let pad_name = Printf.sprintf "__pad_field_%d" !pad_counter in
      let pad_field = {
        fcomp = comp;
        fname = pad_name;
        ftype = intType;
        fbitfield = None;
        fattr = [];
        floc = locUnknown;
      } in

      (* Reverse / permute fields and inject padding *)
      let original_fields = comp.cfields in
      let padded_fields = pad_field :: (List.rev original_fields) in
      comp.cfields <- padded_fields
    )

  let transform_file (f : file) : file =
    List.iter
      (function
        | GCompTag (comp, _) -> permute_and_pad_struct comp
        | GCompTagDecl (comp, _) -> permute_and_pad_struct comp
        | _ -> ())
      f.globals;
    f
end
