open GoblintCil.Cil

(** Domain Service: Specification-Driven random_vISA Virtualization Engine.
    Orchestrates ISA ingestion, register allocation, bytecode compilation,
    slot permutation, XOR encryption, and C11 VCPU kernel synthesis.
    Delegates expression/statement compilation to c_visa_expr_compiler
    and c_visa_stmt_compiler (with two-pass back-patching).
*)
module VisaSpec = C_visa_spec

module Make (Entropy : Entropy_port.S) = struct
  module Spec = C_visa_spec
  module ExprC = C_visa_expr_compiler.Make (Entropy)
  module StmtC = C_visa_stmt_compiler.Make (Entropy)

  let vcpu_counter = ref 0

  let generate_visa_runtime (file : file) : unit =
    let already_injected =
      List.exists
        (function
          | GVarDecl (v, _) when v.vname = "__visa_engine_ready" -> true
          | _ -> false)
        file.globals
    in
    if not already_injected then (
      let flag_var = makeGlobalVar "__visa_engine_ready" intType in
      flag_var.vstorage <- Static;
      file.globals <- (GVarDecl (flag_var, locUnknown)) :: file.globals
    )

  let should_transform (fd : fundec) : bool =
    if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then false
    else if C_annotation_service.AnnotationHelper.should_skip_all fd then false
    else if C_annotation_service.AnnotationHelper.has_annotation fd "visa"
            || C_annotation_service.AnnotationHelper.has_annotation fd "vector_vm"
            || C_annotation_service.AnnotationHelper.has_annotation fd "virtualize" then true
    else not (C_annotation_service.AnnotationHelper.has_any_vm_annotation fd)
         && not (C_annotation_service.AnnotationHelper.has_custom_annotations fd)

  (** Allocate virtual registers for all function formals and locals.
      Returns (get_vreg, next_vreg_ref, max_in_reg). *)
  let alloc_registers spec fd =
    let var_map = Hashtbl.create 32 in
    let in_regs = spec.C_visa_spec.abi.in_regs in
    let get_in_reg idx =
      if idx < List.length in_regs then List.nth in_regs idx else idx
    in
    List.iteri (fun idx p -> Hashtbl.add var_map p.vname (get_in_reg idx)) fd.sformals;
    let max_in_reg =
      List.fold_left (fun acc p -> max acc (Hashtbl.find var_map p.vname)) 0 fd.sformals
    in
    let next_vreg = ref (max (max_in_reg + 1) (List.length fd.sformals)) in
    List.iter
      (fun v ->
        if not (Hashtbl.mem var_map v.vname) then (
          Hashtbl.add var_map v.vname !next_vreg;
          incr next_vreg
        ))
      fd.slocals;
    let get_vreg name =
      if Hashtbl.mem var_map name then Hashtbl.find var_map name
      else (
        let r = !next_vreg in
        incr next_vreg;
        Hashtbl.add var_map name r;
        r
      )
    in
    (get_vreg, next_vreg, get_in_reg)

  (** Permute and XOR-encrypt bytecode words.
      Fix: pack_key uses full 64-bit representation (not truncated to 32 bits). *)
  let pack_bytecode spec n_words vbc_words =
    let rec gcd a b = if b = 0 then a else gcd b (a mod b) in
    let primes = [| 3; 5; 7; 11; 13; 17; 19; 23; 29; 31; 37; 41; 43; 47; 53; 59 |] in
    let coprime_primes =
      Array.to_list primes |> List.filter (fun p -> gcd p n_words = 1)
    in
    let affine_p = match coprime_primes with
      | [] -> 1
      | ps ->
          let idx = Entropy.next_int ~max:(List.length ps) in
          List.nth ps idx
    in
    let affine_s = if n_words > 1 then 1 + (Entropy.next_int ~max:(n_words - 1)) else 0 in
    let pk32 = Int64.to_int32 spec.C_visa_spec.pack_key in
    let dk32 = Int64.to_int32 spec.C_visa_spec.delta_key in
    let permuted_arr = Array.make n_words 0l in
    List.iteri
      (fun idx w ->
        let delta = Int32.mul (Int32.of_int idx) dk32 in
        let key = Int32.logxor pk32 delta in
        let enc = Int32.logxor w key in
        let slot = if n_words > 0 then (idx * affine_p + affine_s) mod n_words else 0 in
        permuted_arr.(slot) <- enc)
      vbc_words;
    (Array.to_list permuted_arr, affine_p, affine_s)

  let type_to_str = function
    | TInt (IULongLong, _) | TInt (ILongLong, _) -> "unsigned long long"
    | TInt (IULong, _) | TInt (ILong, _) -> "unsigned long"
    | TInt (IUInt, _) -> "unsigned int"
    | TPtr (TInt ((IChar | ISChar), _), _) -> "const char *"
    | TPtr (TInt (IUChar, _), _) -> "const unsigned char *"
    | TPtr _ -> "void *"
    | _ -> "int"

  let virtualize_function (file : file) (fd : fundec) : unit =
    if not (should_transform fd) then ()
    else (
      incr vcpu_counter;
      generate_visa_runtime file;

      (* Per-function ISA selection via annotation "vectis:visa:ISA_NAME".
         Falls back to active_spec if no specific ISA is named. *)
      let isa_annotation =
        C_annotation_service.AnnotationHelper.get_tokens fd
        |> List.find_map (fun t ->
            if String.starts_with ~prefix:"visa:" t then
              Some (String.sub t 5 (String.length t - 5))
            else None)
      in
      let spec = Spec.get_spec_for_annotation isa_annotation in
      let op   = spec.opcodes in
      let lay  = spec.layout in

      let vbc_name = Printf.sprintf "__visa_program_%s_%d" fd.svar.vname !vcpu_counter in
      let ptr_formals = List.filter (fun p -> isPointerType p.vtype) fd.sformals in
      let has_ptr_param = ptr_formals <> [] in

      let (get_vreg, next_vreg, get_in_reg) = alloc_registers spec fd in

      (* Compile: two-pass back-patching via StmtC *)
      let vbc_words = StmtC.compile_function spec fd get_vreg next_vreg in
      let n_words = List.length vbc_words in

      (* Pack & encrypt *)
      let (packed_words, affine_p, affine_s) = pack_bytecode spec n_words vbc_words in

      (* Inject bytecode array into CIL globals *)
      let uint_ty = uintType in
      let array_type = TArray (uint_ty, Some (integer (List.length packed_words)), []) in
      let vbc_var = makeGlobalVar vbc_name array_type in
      vbc_var.vstorage <- Static;
      let init_entries =
        List.mapi
          (fun idx w ->
            let u64 = Int64.logand (Int64.of_int32 w) 0xFFFFFFFFL in
            (Index (integer idx, NoOffset),
             SingleInit (Const (CInt (Z.of_int64 u64, IUInt, None)))))
          packed_words
      in
      file.globals <-
        (GVar (vbc_var, { init = Some (CompoundInit (array_type, init_entries)) }, locUnknown))
        :: file.globals;

      let ptr_arg = if has_ptr_param then (List.hd ptr_formals).vname else "0" in
      let vreg_total = max 128 (!next_vreg + 32) in

      let ret_type_str =
        match fd.svar.vtype with TFun (t, _, _, _) -> type_to_str t | _ -> "int"
      in
      let reg_mask_base =
        Int64.logand (Int64.abs (Entropy.next_int64 ())) 0xFFFFFFFFFFFFL
      in
      let reg_mask_step =
        [| 0x9E3779B97F4A7C15L; 0x517CC1B727220A95L; 0x6C62272E07BB0142L |].
          (Entropy.next_int ~max:3)
      in
      let arg_inits =
        List.mapi
          (fun idx p ->
            let target_reg = get_in_reg idx in
            if isIntegralType p.vtype then
              Printf.sprintf "    __VREG_SET(%d, (unsigned long long)%s);" target_reg p.vname
            else if isPointerType p.vtype then
              Printf.sprintf "    __VREG_SET(%d, (unsigned long long)(uintptr_t)%s);"
                target_reg p.vname
            else Printf.sprintf "    __VREG_SET(%d, 0);" target_reg)
          fd.sformals
        |> String.concat "\n"
      in
      let fn_params =
        List.map (fun p -> Printf.sprintf "%s %s" (type_to_str p.vtype) p.vname) fd.sformals
        |> String.concat ", "
      in
      let vreg_rot_seed = Entropy.next_int ~max:64 in

      let fn_body_impl =
        C_visa_c_emitter.emit_function_body
          ~ret_type_str ~fn_name:fd.svar.vname ~fn_params ~vreg_total ~vreg_rot_seed
          ~reg_mask_base ~reg_mask_step ~arg_inits ~ptr_arg ~op ~out_reg:spec.abi.out_reg
          ~affine_p ~affine_s ~word_count:(List.length packed_words)
          ~vbc_name ~pack_key:spec.pack_key ~delta_key:spec.delta_key ~lay
      in

      let new_globals = ref [] in
      List.iter
        (fun g ->
          match g with
          | GFun (f_dec, _) when f_dec.svar.vname = fd.svar.vname ->
              new_globals := GText fn_body_impl :: !new_globals
          | other -> new_globals := other :: !new_globals)
        file.globals;
      file.globals <- List.rev !new_globals
    )

  let transform_file (f : file) : file =
    let funcs =
      List.filter_map
        (function GFun (fd, _) -> Some fd | _ -> None)
        f.globals
    in
    List.iter (virtualize_function f) funcs;
    f
end
