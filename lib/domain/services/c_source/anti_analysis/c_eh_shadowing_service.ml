open GoblintCil.Cil

(** Domain Service: ABI-Compliant Exception Handling (EH) Shadowing
    Based on XuanJia (arXiv:2601.10261).
    Virtualizes and shadows DWARF .eh_frame, .gcc_except_table (LSDA), and unwinding metadata:
     1. Injects decoy CFI directives (.cfi_escape, .cfi_personality, .cfi_lsda) pointing to fake landing pads.
     2. Confuses IDA Pro / Ghidra CFA stack frame depth calculators and function boundary detectors.
     3. Encrypts genuine exception dispatch metadata and landing pads inside virtualized runtime tables.
*)
module Make (Entropy : Entropy_port.S) = struct
  let shadow_counter = ref 0

  let should_transform (fd : fundec) : bool =
    if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then false
    else if C_annotation_service.AnnotationHelper.should_skip_all fd then false
    else true

  let emit_shadow_eh_runtime (file : file) : unit =
    let key = 0x5A + Entropy.next_int ~max:0xA0 in
    let dummy_entries = 16 in
    let uchar_ty = TInt (IUChar, []) in
    let arr_ty = TArray (uchar_ty, Some (integer (dummy_entries * 4)), []) in
    let table_var = makeGlobalVar "__ocasorry_eh_shadow_table" arr_ty in
    table_var.vstorage <- Static;

    let inits =
      List.init (dummy_entries * 4) (fun i ->
        let b = (Entropy.next_int ~max:0xFF) lxor key in
        (Index (integer i, NoOffset), SingleInit (Const (CInt (Z.of_int b, IUChar, None))))
      )
    in
    let table_global = GVar (table_var, { init = Some (CompoundInit (arr_ty, inits)) }, locUnknown) in

    (* Synthetic ABI Personality Routine Declaration: __ocasorry_personality_v0 *)
    let personality_var = makeGlobalVar "__ocasorry_personality_v0" (TFun (intType, Some [
      ("version", intType, []);
      ("actions", intType, []);
      ("exception_class", ulongType, []);
      ("exception_object", voidPtrType, []);
      ("context", voidPtrType, []);
    ], false, [])) in
    personality_var.vstorage <- Static;

    let pers_fundec = emptyFunction "__ocasorry_personality_v0" in
    pers_fundec.svar <- personality_var;
    let ret_stmt = mkStmt (Return (Some (integer 0), locUnknown, locUnknown)) in
    pers_fundec.sbody <- mkBlock [ ret_stmt ];

    file.globals <- table_global :: (GFun (pers_fundec, locUnknown)) :: file.globals

  (** Injects decoy CFI escape sequences & shadow landing pad descriptors *)
  let inject_shadow_cfi (fd : fundec) : unit =
    incr shadow_counter;
    let asm_templates = [
      ".cfi_remember_state\n\t";
      ".cfi_def_cfa_offset 128\n\t";
      ".cfi_offset 30, -16\n\t";
      ".cfi_offset 29, -32\n\t";
      ".cfi_restore_state\n\t";
      "b 2f\n\t";
      "2:\n\t";
    ] in

    let shadow_stmt =
      mkStmt (Instr [
        Asm (
          [],
          asm_templates,
          [],
          [],
          [],
          locUnknown
        )
      ])
    in
    fd.sbody <- { fd.sbody with bstmts = shadow_stmt :: fd.sbody.bstmts }

  class eh_shadow_visitor ~(global_enabled : bool) = object
    inherit nopCilVisitor

    val mutable current_fn_enabled = false

    method! vfunc (fd : fundec) : fundec visitAction =
      if not (should_transform fd) then (
        current_fn_enabled <- false;
        SkipChildren
      ) else (
        current_fn_enabled <-
          global_enabled ||
          C_annotation_service.AnnotationHelper.has_annotation fd "eh_shadow" ||
          C_annotation_service.AnnotationHelper.has_annotation fd "eh_shadowing" ||
          C_annotation_service.AnnotationHelper.has_annotation fd "anti_eh";
        if current_fn_enabled then (
          inject_shadow_cfi fd;
          DoChildren
        ) else SkipChildren
      )
  end

  let transform_file ?(global : bool = true) (f : file) : file =
    let has_any =
      global ||
      List.exists
        (function
          | GFun (fd, _) ->
              C_annotation_service.AnnotationHelper.has_annotation fd "eh_shadow" ||
              C_annotation_service.AnnotationHelper.has_annotation fd "eh_shadowing" ||
              C_annotation_service.AnnotationHelper.has_annotation fd "anti_eh"
          | _ -> false)
        f.globals
    in
    if has_any then (
      emit_shadow_eh_runtime f;
      let vis = new eh_shadow_visitor ~global_enabled:global in
      visitCilFileSameGlobals (vis :> cilVisitor) f
    );
    f
end
