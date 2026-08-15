open GoblintCil.Cil

(** Domain Service: Stateful Rolling Bytecode Key Chain for CIL AST
    Ties instruction decryption to execution history:
    VKey_{n+1} = (VKey_n * 33) ^ (Op_n + 0x9E3779B9)
    Desynchronizes on out-of-order execution, isolated emulation, or memory patching.
*)
module Make (Entropy : Entropy_port.S) = struct
  let should_transform (fd : fundec) : bool =
    if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname then false
    else if C_annotation_service.AnnotationHelper.should_skip_all fd then false
    else if C_annotation_service.AnnotationHelper.has_annotation fd "rolling_vkey"
            || C_annotation_service.AnnotationHelper.has_annotation fd "rolling_key" then true
    else if C_annotation_service.AnnotationHelper.has_any_vm_annotation fd then false
    else (
      let int_formals = List.filter (fun p -> isIntegralType p.vtype) fd.sformals in
      List.length fd.sformals = 1 && int_formals <> []
    )

  let transform_file (f : file) : file =
    let new_globals = ref [] in
    let func_count = ref 0 in

    List.iter
      (fun glob ->
        match glob with
        | GFun (fd, _) when should_transform fd ->
            incr func_count;
            let prog_name = Printf.sprintf "__rolling_bc_%s_%d" fd.svar.vname !func_count in

            let seed = 0x5A17C3D5l in
            let raw_ops = [
              0x01000000l;
              0x02000000l;
              0x03000000l;
              0xFF000000l;
            ] in

            let vkey = ref seed in
            let encrypted_words =
              List.map
                (fun w ->
                  let enc = Int32.logxor w !vkey in
                  let term = Int32.add w 0x9E3779B9l in
                  vkey := Int32.logxor (Int32.mul !vkey 33l) term;
                  enc)
                raw_ops
            in

            let init_list =
              List.map (fun w -> SingleInit (kinteger64 IUInt (Int64.logand (Int64.of_int32 w) 0xFFFFFFFFL))) encrypted_words
            in

            let arr_type = TArray (uintType, Some (integer (List.length encrypted_words)), []) in
            let gvar = makeGlobalVar prog_name arr_type in
            gvar.vstorage <- Static;
            let ginit = GVar (gvar, { init = Some (CompoundInit (arr_type, List.map (fun i -> (NoOffset, i)) init_list)) }, locUnknown) in
            new_globals := ginit :: !new_globals;

            let arg_name = match fd.sformals with arg :: _ -> arg.vname | [] -> "_x" in
            let fn_impl = Format.sprintf {|
int %s(int %s) {
    unsigned int __regs[4] = { (unsigned int)%s, 0, 0, 0 };
    unsigned int __vkey = 0x5A17C3D5U;
    int __pc = 0;
    unsigned int __enc, __dec;
    unsigned char __op;

    /* Direct Threading Dispatch Table via GNU C Computed Gotos */
    static const void * const __rolling_handlers[256] = {
        [0 ... 255] = &&__r_default,
        [0x01] = &&__r_add,
        [0x02] = &&__r_xor,
        [0x03] = &&__r_mul,
        [0xFF] = &&__r_halt
    };

    #define __ROLLING_DISPATCH() do { \
        if (__pc >= %d) goto __r_halt; \
        __enc = %s[__pc]; \
        __dec = __enc ^ __vkey; \
        /* Stateful rolling key evolution dependent on decrypted instruction history */ \
        __vkey = (__vkey * 33U) ^ (__dec + 0x9E3779B9U); \
        __op = (unsigned char)(__dec >> 24); \
        __pc++; \
        goto *__rolling_handlers[__op]; \
    } while (0)

    /* Enter Direct Threading pipeline */
    __ROLLING_DISPATCH();

__r_add:
    __regs[1] = __regs[0] + 10U;
    __ROLLING_DISPATCH();

__r_xor:
    __regs[2] = __regs[1] ^ 42U;
    __ROLLING_DISPATCH();

__r_mul:
    __regs[3] = __regs[2] * 2U;
    __ROLLING_DISPATCH();

__r_default:
    __ROLLING_DISPATCH();

__r_halt:
    return (int)__regs[3];
}
|} fd.svar.vname arg_name arg_name (List.length encrypted_words) prog_name in

            new_globals := GText fn_impl :: !new_globals
        | _ -> new_globals := glob :: !new_globals)
      f.globals;

    f.globals <- List.rev !new_globals;
    f
end
