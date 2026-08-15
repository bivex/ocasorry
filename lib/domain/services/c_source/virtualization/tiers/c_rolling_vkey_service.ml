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

            (* Per-build randomized key schedule (was: hardcoded
               0x5A17C3D5 / 33 / 0x9E3779B9 — identical across every build).
               Odd multiplier keeps the LCG invertible mod 2^32; odd nonzero
               seed/delta avoid degenerate short cycles. The encryptor below
               and the emitted C decryptor consume the SAME draws within one
               transform_file invocation — lockstep by construction. *)
            let vkey_seed =
              Int32.logor (Int32.logand (Entropy.next_int32 ()) 0xFFFFFFFEl) 1l in
            let lcg_mult =
              Int32.of_int ((17 + Entropy.next_int ~max:0xFE01) lor 1) in
            let lcg_delta =
              Int32.logor (Int32.logand (Entropy.next_int32 ()) 0xFFFFFFFEl) 1l in
            (* Distinct randomized opcode bytes (was: fixed 0x01/0x02/0x03/0xFF).
               Both the encrypted program and the C dispatch table slots derive
               from this single shuffle. *)
            let op_pool =
              [| 0x01; 0x02; 0x03; 0x04; 0x05; 0x06; 0x07; 0x08; 0x09; 0x0A;
                 0x10; 0x20; 0x40; 0x80 |] in
            let shuffled =
              Array.of_list (Entropy.shuffle (Array.to_list op_pool)) in
            let (op_add, op_xor, op_mul, op_halt) =
              (shuffled.(0), shuffled.(1), shuffled.(2), shuffled.(3)) in
            let raw_ops =
              List.map (fun b -> Int32.shift_left (Int32.of_int b) 24)
                [ op_add; op_xor; op_mul; op_halt ]
            in

            let vkey = ref vkey_seed in
            let encrypted_words =
              List.map
                (fun w ->
                  let enc = Int32.logxor w !vkey in
                  let term = Int32.add w lcg_delta in
                  vkey := Int32.logxor (Int32.mul !vkey lcg_mult) term;
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
    unsigned int __vkey = 0x%lXU;
    int __pc = 0;
    unsigned int __enc, __dec;
    unsigned char __op;

    /* Direct Threading Dispatch Table via GNU C Computed Gotos */
    static const void * const __rolling_handlers[256] = {
        [0 ... 255] = &&__r_default,
        [0x%02X] = &&__r_add,
        [0x%02X] = &&__r_xor,
        [0x%02X] = &&__r_mul,
        [0x%02X] = &&__r_halt
    };

    #define __ROLLING_DISPATCH() do { \
        if (__pc >= %d) goto __r_halt; \
        __enc = %s[__pc]; \
        __dec = __enc ^ __vkey; \
        /* Stateful rolling key evolution dependent on decrypted instruction history */ \
        __vkey = (__vkey * 0x%lXU) ^ (__dec + 0x%lXU); \
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

__r_halt: ;
    int __ret_val = (int)__regs[3];
    __builtin_memset(__regs, 0, sizeof(__regs));
    return __ret_val;
}
|} fd.svar.vname arg_name arg_name vkey_seed
      op_add op_xor op_mul op_halt
      (List.length encrypted_words) prog_name lcg_mult lcg_delta in

            new_globals := GText fn_impl :: !new_globals
        | _ -> new_globals := glob :: !new_globals)
      f.globals;

    f.globals <- List.rev !new_globals;
    f
end
