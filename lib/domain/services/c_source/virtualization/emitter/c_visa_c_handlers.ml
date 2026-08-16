(** Domain Service: C11 Opcode Handlers Generator for vISA Virtual Machines
    Generates C11 code for all ALU, bitwise, memory load/store, and branching operations.
    Features:
    - Dynamic Polymorphic AArch64 JIT Machine Code Synthesis with Safe Decoys (WZR/NOP).
    - Session-Key XOR Encryption of JIT Instruction Buffers in .rodata.
    - Ephemeral Micro-Allocation with 3-Pass DoD 5220.22-M Memory Sanitization.
*)

let generate_vjit_insns ~k1 ~k2 =
  let enc_mov_x2 imm =
    Int32.logor 0xD2800002l (Int32.shift_left (Int32.of_int (imm land 0xFFFF)) 5)
  in
  let enc_add_imm_x0 imm =
    Int32.logor 0x91000000l (Int32.shift_left (Int32.of_int (imm land 0xFFF)) 10)
  in
  let decoys = [
    0xCA1F031Fl; (* eor xzr, xzr, xzr *)
    0xAA1F031Fl; (* mov xzr, xzr *)
    0xD503201Fl; (* nop *)
  ] in
  let d1 = List.nth decoys (Random.int (List.length decoys)) in
  let d2 = List.nth decoys (Random.int (List.length decoys)) in
  let d3 = List.nth decoys (Random.int (List.length decoys)) in
  [
    0xCA010000l;         (* eor x0, x0, x1 *)
    d1;                  (* polymorphic decoy *)
    enc_mov_x2 k1;       (* mov x2, #k1 *)
    0x9B027C00l;         (* mul x0, x0, x2 *)
    d2;                  (* polymorphic decoy *)
    enc_add_imm_x0 k2;   (* add x0, x0, #k2 *)
    d3;                  (* polymorphic decoy *)
    0xD65F03C0l;         (* ret *)
  ]

let generate_vjit_alt1_insns ~k3 ~k4 =
  let enc_mov_x2 imm =
    Int32.logor 0xD2800002l (Int32.shift_left (Int32.of_int (imm land 0xFFFF)) 5)
  in
  let decoys = [
    0xCA1F031Fl; (* eor xzr, xzr, xzr *)
    0xAA1F031Fl; (* mov xzr, xzr *)
    0xD503201Fl; (* nop *)
  ] in
  let d1 = List.nth decoys (Random.int (List.length decoys)) in
  let d2 = List.nth decoys (Random.int (List.length decoys)) in
  let d3 = List.nth decoys (Random.int (List.length decoys)) in
  [
    0x8B010000l;         (* add x0, x0, x1 *)
    d1;                  (* polymorphic decoy *)
    enc_mov_x2 k3;       (* mov x2, #k3 *)
    0xCA020000l;         (* eor x0, x0, x2 *)
    d2;                  (* polymorphic decoy *)
    enc_mov_x2 k4;       (* mov x2, #k4 *)
    0x9B027C00l;         (* mul x0, x0, x2 *)
    d3;                  (* polymorphic decoy *)
    0xD65F03C0l;         (* ret *)
  ]

let emit_handlers ~(trap_code : string) ~(vd_shift : int) : string =
  let branch_target_line =
    Printf.sprintf "    unsigned int __branch_target = (__inst >> %d) & 0xFFU;\n" vd_shift
  in

  (* Dynamic per-instance constants for JIT polymorphic transformations *)
  let k1_choices = [| 3; 5; 7; 9; 11; 13; 15; 17; 19; 21 |] in
  let k2_choices = [| 13; 27; 42; 57; 73; 91; 105; 127 |] in
  let k3_choices = [| 0x1A; 0x2B; 0x3C; 0x4D; 0x5A; 0x6E; 0x7F |] in
  let k4_choices = [| 3; 5; 7; 11; 13; 17 |] in

  let k1 = k1_choices.(Random.int (Array.length k1_choices)) in
  let k2 = k2_choices.(Random.int (Array.length k2_choices)) in
  let k3 = k3_choices.(Random.int (Array.length k3_choices)) in
  let k4 = k4_choices.(Random.int (Array.length k4_choices)) in

  let insns1 = generate_vjit_insns ~k1 ~k2 in
  let insns2 = generate_vjit_alt1_insns ~k3 ~k4 in

  let key1 = Int32.logor (Int32.of_int (Random.bits ())) 0x10000001l in
  let key2 = Int32.logor (Int32.of_int (Random.bits ())) 0x20000001l in

  let enc_insns1_str =
    List.map (fun w -> Printf.sprintf "0x%08lXU" (Int32.logxor w key1)) insns1
    |> String.concat ", "
  in
  let enc_insns2_str =
    List.map (fun w -> Printf.sprintf "0x%08lXU" (Int32.logxor w key2)) insns2
    |> String.concat ", "
  in

  trap_code ^ Printf.sprintf {|
__h_vadd: {
    unsigned long long __a = __VREG_GET(__vs1), __b = __VREG_GET(__vs2);
    __VREG_SET(__vd, (__a ^ __b) + ((__a & __b) << 1));
    __VISA_DISPATCH();
}
__h_vadd_alt1: {
    unsigned long long __a = __VREG_GET(__vs1), __b = __VREG_GET(__vs2);
    __VREG_SET(__vd, (__a | __b) + (__a & __b));
    __VISA_DISPATCH();
}
__h_vadd_alt2: {
    unsigned long long __a = __VREG_GET(__vs1), __b = __VREG_GET(__vs2);
    __VREG_SET(__vd, ((__a | __b) << 1) - (__a ^ __b));
    __VISA_DISPATCH();
}
__h_vsub: {
    unsigned long long __a = __VREG_GET(__vs1), __b = __VREG_GET(__vs2);
    __VREG_SET(__vd, (__a ^ __b) - ((~__a & __b) << 1));
    __VISA_DISPATCH();
}
__h_vsub_alt1: {
    unsigned long long __a = __VREG_GET(__vs1), __b = __VREG_GET(__vs2);
    __VREG_SET(__vd, (__a & ~__b) - (~__a & __b));
    __VISA_DISPATCH();
}
__h_vsub_alt2: {
    unsigned long long __a = __VREG_GET(__vs1), __b = __VREG_GET(__vs2);
    __VREG_SET(__vd, (__a ^ ~__b) + 1ULL + ((__a & ~__b) << 1));
    __VISA_DISPATCH();
}
__h_vmul:
    __VREG_SET(__vd, (unsigned long long)(__VREG_GET(__vs1) * __VREG_GET(__vs2)));
    __VISA_DISPATCH();
__h_vmul_alt1:
    __VREG_SET(__vd, (unsigned long long)((__VREG_GET(__vs1) ^ 0) * (__VREG_GET(__vs2) ^ 0)));
    __VISA_DISPATCH();
__h_vxor: {
    unsigned long long __a = __VREG_GET(__vs1), __b = __VREG_GET(__vs2);
    __VREG_SET(__vd, (__a | __b) - (__a & __b));
    __VISA_DISPATCH();
}
__h_vxor_alt1: {
    unsigned long long __a = __VREG_GET(__vs1), __b = __VREG_GET(__vs2);
    __VREG_SET(__vd, (~__a & __b) + (__a & ~__b));
    __VISA_DISPATCH();
}
__h_vxor_alt2: {
    unsigned long long __a = __VREG_GET(__vs1), __b = __VREG_GET(__vs2);
    __VREG_SET(__vd, (__a + __b) - ((__a & __b) << 1));
    __VISA_DISPATCH();
}
__h_vand: {
    unsigned long long __a = __VREG_GET(__vs1), __b = __VREG_GET(__vs2);
    __VREG_SET(__vd, (__a | __b) - (__a ^ __b));
    __VISA_DISPATCH();
}
__h_vand_alt1: {
    unsigned long long __a = __VREG_GET(__vs1), __b = __VREG_GET(__vs2);
    __VREG_SET(__vd, (__a + __b) - (__a | __b));
    __VISA_DISPATCH();
}
__h_vor: {
    unsigned long long __a = __VREG_GET(__vs1), __b = __VREG_GET(__vs2);
    __VREG_SET(__vd, (__a & __b) + (__a ^ __b));
    __VISA_DISPATCH();
}
__h_vor_alt1: {
    unsigned long long __a = __VREG_GET(__vs1), __b = __VREG_GET(__vs2);
    __VREG_SET(__vd, (__a + __b) - (__a & __b));
    __VISA_DISPATCH();
}
__h_vsll: {
    unsigned long long __a = __VREG_GET(__vs1), __sh = __VREG_GET(__vs2) & 0x3FULL;
    __VREG_SET(__vd, __a << __sh);
    __VISA_DISPATCH();
}
__h_vsrl: {
    unsigned long long __a = __VREG_GET(__vs1), __sh = __VREG_GET(__vs2) & 0x3FULL;
    __VREG_SET(__vd, (unsigned long long)(__a >> __sh));
    __VISA_DISPATCH();
}
__h_vli:
    __VREG_SET(__vd, (unsigned long long)((__vm << 13) | (__funct3 << 10) | (__vs1 << 5) | __vs2));
    __VISA_DISPATCH();
__h_vli_alt1:
    __VREG_SET(__vd, (unsigned long long)((((__vm << 3) | __funct3) << 10) | (__vs1 << 5) | __vs2));
    __VISA_DISPATCH();
__h_vmv:
    __VREG_SET(__vd, __VREG_GET(__vs1));
    __VISA_DISPATCH();
__h_vmv_alt1:
    __VREG_SET(__vd, __VREG_GET(__vs1) ^ 0);
    __VISA_DISPATCH();
__h_vle8: {
    const unsigned char *__load_base = (const unsigned char *)(uintptr_t)__VREG_GET(__vs1);
    if (__load_base) {
        __VREG_SET(__vd, (unsigned long long)__load_base[__VREG_GET(__vs2)]);
    }
    __VISA_DISPATCH();
}
__h_vse8:
    if (__vsp_d < 63) {
        __vstack_data[__vsp_d++] = __VREG_GET(__vs1);
    }
    __VISA_DISPATCH();
__h_vbge: {
%s
    if (__VREG_GET(__vs1) >= __VREG_GET(__vs2)) {
        __pc = (unsigned int)((__branch_target) + ((__vm_state_acc * (__vm_state_acc + 1ULL)) & 1ULL));
    }
    __VISA_DISPATCH();
}
__h_vj: {
    unsigned int __jump_target = (__inst >> 7) & 0x7FFFFU;
    __pc = (unsigned int)((__jump_target) + ((__vm_state_acc * (__vm_state_acc + 1ULL)) & 1ULL));
    __VISA_DISPATCH();
}
__h_vjit: {
    /* Architecture A: Polymorphic In-VM Ephemeral AArch64 JIT Escape Gate */
    unsigned long long __a = __VREG_GET(__vs1), __b = __VREG_GET(__vs2);
    size_t __jit_sz = 0;
    static const uint32_t __vjit_enc_insns[%d] = { %s };
    const uint32_t __vjit_key = 0x%08lXU;
    size_t __jit_code_sz = sizeof(__vjit_enc_insns);
    unsigned char *__jpage = (unsigned char *)__vectis_vm_alloc_ephemeral_page(&__jit_sz, __jit_code_sz);
    if (__jpage) {
#if defined(__APPLE__) && (defined(__aarch64__) || defined(__arm64__))
        pthread_jit_write_protect_np(0);
#endif
        for (size_t __i = 0; __i < sizeof(__vjit_enc_insns)/sizeof(uint32_t); ++__i) {
            ((uint32_t *)__jpage)[__i] = __vjit_enc_insns[__i] ^ __vjit_key;
        }
#if defined(__APPLE__) && (defined(__aarch64__) || defined(__arm64__))
        pthread_jit_write_protect_np(1);
        sys_icache_invalidate(__jpage, __jit_code_sz);
#elif defined(__aarch64__) || defined(__arm64__)
        __builtin___clear_cache((char *)__jpage, (char *)__jpage + __jit_code_sz);
#endif
        typedef unsigned long long (*__vjit_fn_t)(unsigned long long, unsigned long long);
        volatile __vjit_fn_t __jfn = (__vjit_fn_t)(void *)__jpage;
        unsigned long long __jres = __jfn(__a, __b);
        __vectis_vm_free_ephemeral_page(__jpage, __jit_sz);
        __VREG_SET(__vd, __jres);
    } else {
        __VREG_SET(__vd, ((__a ^ __b) * %dULL) + %dULL);
    }
    __VISA_DISPATCH();
}
__h_vjit_alt1: {
    /* Architecture A: Polymorphic In-VM Ephemeral AArch64 JIT Escape Gate (Alt Alias) */
    unsigned long long __a = __VREG_GET(__vs1), __b = __VREG_GET(__vs2);
    size_t __jit_sz = 0;
    static const uint32_t __vjit_alt1_enc_insns[%d] = { %s };
    const uint32_t __vjit_alt1_key = 0x%08lXU;
    size_t __jit_code_sz = sizeof(__vjit_alt1_enc_insns);
    unsigned char *__jpage = (unsigned char *)__vectis_vm_alloc_ephemeral_page(&__jit_sz, __jit_code_sz);
    if (__jpage) {
#if defined(__APPLE__) && (defined(__aarch64__) || defined(__arm64__))
        pthread_jit_write_protect_np(0);
#endif
        for (size_t __i = 0; __i < sizeof(__vjit_alt1_enc_insns)/sizeof(uint32_t); ++__i) {
            ((uint32_t *)__jpage)[__i] = __vjit_alt1_enc_insns[__i] ^ __vjit_alt1_key;
        }
#if defined(__APPLE__) && (defined(__aarch64__) || defined(__arm64__))
        pthread_jit_write_protect_np(1);
        sys_icache_invalidate(__jpage, __jit_code_sz);
#elif defined(__aarch64__) || defined(__arm64__)
        __builtin___clear_cache((char *)__jpage, (char *)__jpage + __jit_code_sz);
#endif
        typedef unsigned long long (*__vjit_fn_t)(unsigned long long, unsigned long long);
        volatile __vjit_fn_t __jfn = (__vjit_fn_t)(void *)__jpage;
        unsigned long long __jres = __jfn(__a, __b);
        __vectis_vm_free_ephemeral_page(__jpage, __jit_sz);
        __VREG_SET(__vd, __jres);
    } else {
        __VREG_SET(__vd, ((__a + __b) ^ 0x%XULL) * %dULL);
    }
    __VISA_DISPATCH();
}
__h_default:
    __builtin_trap();
|}
    branch_target_line
    (List.length insns1) enc_insns1_str key1 k1 k2
    (List.length insns2) enc_insns2_str key2 k3 k4
