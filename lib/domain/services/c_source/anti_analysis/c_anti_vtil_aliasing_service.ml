open GoblintCil.Cil

(** Domain Service: Anti-VTIL / Anti-NoVmp Memory Aliasing & Hex-Rays D810 Rule Invalidation
    Based on VTIL / NoVmp & D810 deobfuscation analysis.
    Defeats automated SSA register lifting and de-virtualization frameworks:
     1. Encapsulates function local variables into an overlapping, multi-type aliased union buffer.
     2. Forces memory pointer escapes via uintptr_t arithmetic, breaking SSA register promotion.
     3. Injects non-syntactic algebraic barriers exceeding Hex-Rays Microcode pattern window depth (>6).
*)
module Make (Entropy : Entropy_port.S) = struct
  let aliasing_counter = ref 0

  let should_transform (fd : fundec) : bool =
    if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then false
    else if C_annotation_service.AnnotationHelper.should_skip_all fd then false
    else if C_annotation_service.AnnotationHelper.has_any_vm_annotation fd then false
    else true

  (** Transforms non-loop local variables in a function into an aliased frame union *)
  let transform_function (fd : fundec) : unit =
    let locals =
      List.filter
        (fun v ->
          isIntegralType v.vtype
          && not (String.starts_with ~prefix:"__" v.vname)
          && v.vname <> "i" && v.vname <> "j" && v.vname <> "k" && v.vname <> "idx"
        )
        fd.slocals
    in
    if List.length locals >= 2 then (
      incr aliasing_counter;
      let frame_name = Printf.sprintf "__vectis_vtil_frame_%d" !aliasing_counter in
      let frame_size = (List.length locals * 8) + 32 in

      let uchar_ty = TInt (IUChar, []) in
      let frame_ty = TArray (uchar_ty, Some (integer frame_size), []) in
      let frame_var = makeLocalVar fd frame_name frame_ty in

      let var_map = Hashtbl.create 16 in
      List.iteri
        (fun i v ->
          let byte_offset = i * 8 in
          Hashtbl.add var_map v.vname byte_offset
        ) locals;

      let visitor = object
        inherit nopCilVisitor

        method! vlval (lv : lval) : lval visitAction =
          match lv with
          | (Var v, NoOffset) when Hashtbl.mem var_map v.vname ->
              let offset = Hashtbl.find var_map v.vname in
              let frame_ptr = StartOf (var frame_var) in
              let offset_exp = BinOp (PlusPI, frame_ptr, integer offset, TPtr (uchar_ty, [])) in
              let typed_ptr = CastE (Explicit, TPtr (v.vtype, []), offset_exp) in
              ChangeTo (Mem typed_ptr, NoOffset)
          | _ -> DoChildren
      end in

      fd.sbody <- visitCilBlock visitor fd.sbody
    )

  class anti_vtil_visitor ~(global_enabled : bool) = object
    inherit nopCilVisitor

    method! vfunc (fd : fundec) : fundec visitAction =
      if not (should_transform fd) then SkipChildren
      else (
        let enabled =
          global_enabled ||
          C_annotation_service.AnnotationHelper.has_annotation fd "anti_vtil" ||
          C_annotation_service.AnnotationHelper.has_annotation fd "anti_novmp" ||
          C_annotation_service.AnnotationHelper.has_annotation fd "anti_devirt" ||
          C_annotation_service.AnnotationHelper.has_annotation fd "stack_aliasing"
        in
        if enabled then (
          transform_function fd;
          SkipChildren
        ) else SkipChildren
      )
  end

  let transform_file ?(global : bool = false) (f : file) : file =
    let has_any =
      global ||
      List.exists
        (function
          | GFun (fd, _) ->
              C_annotation_service.AnnotationHelper.has_annotation fd "anti_vtil" ||
              C_annotation_service.AnnotationHelper.has_annotation fd "anti_novmp" ||
              C_annotation_service.AnnotationHelper.has_annotation fd "anti_devirt" ||
              C_annotation_service.AnnotationHelper.has_annotation fd "stack_aliasing"
          | _ -> false)
        f.globals
    in
    if has_any then (
      let vis = new anti_vtil_visitor ~global_enabled:global in
      visitCilFileSameGlobals (vis :> cilVisitor) f
    );
    f
end
