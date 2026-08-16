open C_arm64_edsl
open C_visa_c_runtime


(** Domain Service: C11 Opcode Handlers Generator for vISA Virtual Machines
    Generates C11 code for all ALU, bitwise, memory load/store, and branching operations.
    Features:
    - Typed AArch64 Machine Code Generation via C_arm64_edsl.
    - Session-Key XOR Encryption of JIT Instruction Buffers in .rodata.
    - Ephemeral Micro-Allocation with 3-Pass DoD 5220.22-M Memory Sanitization.
*)

let generate_vjit_insns ~k1 ~k2 =
  let prog =
    empty
    <+> Eor (X0, X0, X1)
    <+> Decoy `ZeroLogic
    <+> MovImm (X2, k1)
    <+> Mul (X0, X0, X2)
    <+> Decoy `Nop
    <+> AddImm (X0, X0, k2)
    <+> Decoy `ZeroLogic
    <+> Ret
  in
  assemble ~insert_decoys:false prog

let generate_vjit_alt1_insns ~k3 ~k4 =
  let prog =
    empty
    <+> Add (X0, X0, X1)
    <+> Decoy `ZeroLogic
    <+> MovImm (X2, k3)
    <+> Eor (X0, X0, X2)
    <+> Decoy `Nop
    <+> MovImm (X2, k4)
    <+> Mul (X0, X0, X2)
    <+> Decoy `ZeroLogic
    <+> Ret
  in
  assemble ~insert_decoys:false prog

(* ── MBA form pools with 3-variable state-entangled invariants ── *)

let vadd_forms (vs : C_visa_c_runtime.var_set) = [|
  Printf.sprintf "__VREG_SET(%s, (__a ^ __b) + ((__a & __b) << 1) + (((unsigned long long)%s * ((unsigned long long)%s + 1ULL)) & 1ULL))" vs.vd vs.ky vs.ky;
  Printf.sprintf "__VREG_SET(%s, (__a | __b) + (__a & __b) + (((unsigned long long)%s * ((unsigned long long)%s + 1ULL)) & 1ULL))" vs.vd vs.fae vs.fae;
  Printf.sprintf "__VREG_SET(%s, ((__a | __b) << 1) - (__a ^ __b))" vs.vd;
  Printf.sprintf "__VREG_SET(%s, (__a + __b) ^ (((unsigned long long)%s * ((unsigned long long)%s + 1ULL)) & 1ULL))" vs.vd vs.pc vs.pc;
  Printf.sprintf "__VREG_SET(%s, (__a + __b + 1ULL) - 1ULL)" vs.vd;
|]

let vsub_forms (vs : C_visa_c_runtime.var_set) = [|
  Printf.sprintf "__VREG_SET(%s, (__a ^ __b) - ((~__a & __b) << 1) + (((unsigned long long)%s * ((unsigned long long)%s + 1ULL)) & 1ULL))" vs.vd vs.ky vs.ky;
  Printf.sprintf "__VREG_SET(%s, (__a & ~__b) - (~__a & __b))" vs.vd;
  Printf.sprintf "__VREG_SET(%s, (__a ^ ~__b) + 1ULL + ((__a & ~__b) << 1))" vs.vd;
  Printf.sprintf "__VREG_SET(%s, (__a - __b) ^ (((unsigned long long)%s * ((unsigned long long)%s + 1ULL)) & 1ULL))" vs.vd vs.fae vs.fae;
|]

let vmul_forms (vs : C_visa_c_runtime.var_set) = [|
  Printf.sprintf "__VREG_SET(%s, (unsigned long long)(__a * __b))" vs.vd;
  Printf.sprintf "__VREG_SET(%s, (unsigned long long)((__a ^ 0) * (__b ^ 0)) + (((unsigned long long)%s * ((unsigned long long)%s + 1ULL)) & 1ULL))" vs.vd vs.ky vs.ky;
  Printf.sprintf "__VREG_SET(%s, (unsigned long long)((__a + 0ULL) * (__b + 0ULL)))" vs.vd;
|]

let vxor_forms (vs : C_visa_c_runtime.var_set) = [|
  Printf.sprintf "__VREG_SET(%s, ((__a | __b) - (__a & __b)) + (((unsigned long long)%s * ((unsigned long long)%s + 1ULL)) & 1ULL))" vs.vd vs.ky vs.ky;
  Printf.sprintf "__VREG_SET(%s, (~__a & __b) + (__a & ~__b))" vs.vd;
  Printf.sprintf "__VREG_SET(%s, (__a + __b) - ((__a & __b) << 1))" vs.vd;
  Printf.sprintf "__VREG_SET(%s, (__a ^ __b) ^ (((unsigned long long)%s * ((unsigned long long)%s + 1ULL)) & 1ULL))" vs.vd vs.pc vs.pc;
|]

let vand_forms (vs : C_visa_c_runtime.var_set) = [|
  Printf.sprintf "__VREG_SET(%s, ((__a | __b) - (__a ^ __b)) + (((unsigned long long)%s * ((unsigned long long)%s + 1ULL)) & 1ULL))" vs.vd vs.fae vs.fae;
  Printf.sprintf "__VREG_SET(%s, (__a + __b) - (__a | __b))" vs.vd;
  Printf.sprintf "__VREG_SET(%s, __a & __b)" vs.vd;
|]

let vor_forms (vs : C_visa_c_runtime.var_set) = [|
  Printf.sprintf "__VREG_SET(%s, ((__a & __b) + (__a ^ __b)) + (((unsigned long long)%s * ((unsigned long long)%s + 1ULL)) & 1ULL))" vs.vd vs.ky vs.ky;
  Printf.sprintf "__VREG_SET(%s, (__a + __b) - (__a & __b))" vs.vd;
  Printf.sprintf "__VREG_SET(%s, __a | __b)" vs.vd;
|]

let pick arr = arr.(Random.int (Array.length arr))

let emit_disp vs =
  let r = Random.int 3 in
  if r = 0 then
    Printf.sprintf "if (((unsigned long long)%s * ((unsigned long long)%s + 1ULL)) & 1ULL) { goto __h_vret; } else { __VISA_DISPATCH(); }" vs.ky vs.ky
  else if r = 1 then
    Printf.sprintf "if (((unsigned long long)%s * ((unsigned long long)%s + 1ULL)) & 1ULL) { __VISA_DISPATCH(); } else { __VISA_DISPATCH(); }" vs.fae vs.fae
  else
    "__VISA_DISPATCH();"

(* Inline volatile decoy between handlers — unique per build *)
let decoy_stmt () =
  let tag = Printf.sprintf "%04x%04x" (Random.int 0xFFFF) (Random.int 0xFFFF) in
  let v   = Printf.sprintf "0x%LXULL" (Random.int64 Int64.max_int) in
  Printf.sprintf
    "\n    { volatile unsigned long long __dcb_%s = %s; (void)__dcb_%s; }\n"
    tag v tag



let emit_handlers
    ~(vs : C_visa_c_runtime.var_set)
    ~(trap_code : string)
    ~(vd_shift : int) : string =
  let branch_target_line =
    Printf.sprintf "    unsigned int __branch_target = (%s >> %d) & 0xFFU;\n" vs.ins vd_shift
  in
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
  let (enc_insns1_str, key1, len1) = to_encrypted_c_array insns1 in
  let (enc_insns2_str, key2, len2) = to_encrypted_c_array insns2 in
  (* Pick random MBA forms — pass vs so forms use randomized names & state registers *)
  let f_vadd  = pick (vadd_forms vs) in
  let f_vadd1 = pick (vadd_forms vs) in
  let f_vadd2 = pick (vadd_forms vs) in
  let f_vsub  = pick (vsub_forms vs) in
  let f_vsub1 = pick (vsub_forms vs) in
  let f_vsub2 = pick (vsub_forms vs) in
  let f_vmul  = pick (vmul_forms vs) in
  let f_vmul1 = pick (vmul_forms vs) in
  let f_vxor  = pick (vxor_forms vs) in
  let f_vxor1 = pick (vxor_forms vs) in
  let f_vxor2 = pick (vxor_forms vs) in
  let f_vand  = pick (vand_forms vs) in
  let f_vand1 = pick (vand_forms vs) in
  let f_vor   = pick (vor_forms  vs) in
  let f_vor1  = pick (vor_forms  vs) in
  let d1 = emit_disp vs in
  let d2 = emit_disp vs in
  let d3 = emit_disp vs in
  let d4 = emit_disp vs in
  let d5 = emit_disp vs in
  let d6 = emit_disp vs in
  trap_code ^ Printf.sprintf {|
__h_vadd: {
    unsigned long long __a = __VREG_GET(%s), __b = __VREG_GET(%s);
    %s;
    %s
}
__h_vadd_alt1: {
    unsigned long long __a = __VREG_GET(%s), __b = __VREG_GET(%s);
    %s;
    %s
}
__h_vadd_alt2: {
    unsigned long long __a = __VREG_GET(%s), __b = __VREG_GET(%s);
    %s;
    %s
}
%s
__h_vsub: {
    unsigned long long __a = __VREG_GET(%s), __b = __VREG_GET(%s);
    %s;
    %s
}
__h_vsub_alt1: {
    unsigned long long __a = __VREG_GET(%s), __b = __VREG_GET(%s);
    %s;
    %s
}
__h_vsub_alt2: {
    unsigned long long __a = __VREG_GET(%s), __b = __VREG_GET(%s);
    %s;
    %s
}
%s
__h_vmul: {
    unsigned long long __a = __VREG_GET(%s), __b = __VREG_GET(%s);
    %s;
    __VISA_DISPATCH();
}
__h_vmul_alt1: {
    unsigned long long __a = __VREG_GET(%s), __b = __VREG_GET(%s);
    %s;
    __VISA_DISPATCH();
}
%s
__h_vxor: {
    unsigned long long __a = __VREG_GET(%s), __b = __VREG_GET(%s);
    %s;
    __VISA_DISPATCH();
}
__h_vxor_alt1: {
    unsigned long long __a = __VREG_GET(%s), __b = __VREG_GET(%s);
    %s;
    __VISA_DISPATCH();
}
__h_vxor_alt2: {
    unsigned long long __a = __VREG_GET(%s), __b = __VREG_GET(%s);
    %s;
    __VISA_DISPATCH();
}
%s
__h_vand: {
    unsigned long long __a = __VREG_GET(%s), __b = __VREG_GET(%s);
    %s;
    __VISA_DISPATCH();
}
__h_vand_alt1: {
    unsigned long long __a = __VREG_GET(%s), __b = __VREG_GET(%s);
    %s;
    __VISA_DISPATCH();
}
%s
__h_vor: {
    unsigned long long __a = __VREG_GET(%s), __b = __VREG_GET(%s);
    %s;
    __VISA_DISPATCH();
}
__h_vor_alt1: {
    unsigned long long __a = __VREG_GET(%s), __b = __VREG_GET(%s);
    %s;
    __VISA_DISPATCH();
}

__h_vsll: {
    unsigned long long __a = __VREG_GET(%s), __sh = __VREG_GET(%s) & 0x3FULL;
    __VREG_SET(%s, __a << __sh);
    __VISA_DISP_SHIFT();
}
__h_vsrl: {
    unsigned long long __a = __VREG_GET(%s), __sh = __VREG_GET(%s) & 0x3FULL;
    __VREG_SET(%s, (unsigned long long)(__a >> __sh));
    __VISA_DISP_SHIFT();
}
__h_vli:
    __VREG_SET(%s, (unsigned long long)((%s << 13) | (%s << 10) | (%s << 5) | %s));
    __VISA_DISPATCH();
__h_vli_alt1:
    __VREG_SET(%s, (unsigned long long)(((%s << 3) | %s) << 10) | (%s << 5) | %s);

    __VISA_DISPATCH();
__h_vmv:
    __VREG_SET(%s, __VREG_GET(%s));
    __VISA_DISPATCH();
__h_vmv_alt1:
    __VREG_SET(%s, __VREG_GET(%s) ^ 0);
    __VISA_DISPATCH();
__h_vle8: {
    const unsigned char *__load_base = (const unsigned char *)(uintptr_t)__VREG_GET(%s);
    if (__load_base) {
        __VREG_SET(%s, (unsigned long long)__load_base[__VREG_GET(%s)]);
    }
    __VISA_DISP_MEM();
}
__h_vse8:
    if (%s < %d) {
        %s[%s++] = __VREG_GET(%s);
    }
    __VISA_DISP_MEM();
__h_vbge: {
%s
    /* Anti-Concolic Cryptographic ARX Path Trap (Vector 5) */
    unsigned long long __arx_v = (unsigned long long)%s;
    unsigned long long __arx_k = 0x9E3779B97F4A7C15ULL;
    __arx_v += __arx_k;
    __arx_k = ((__arx_k << 13) | (__arx_k >> 51)) ^ __arx_v;
    __arx_v = ((__arx_v << 32) | (__arx_v >> 32)) + __arx_k;
    __arx_k = ((__arx_k << 16) | (__arx_k >> 48)) ^ __arx_v;
    if (__VREG_GET(%s) >= __VREG_GET(%s)) {
        %s = (unsigned int)((__branch_target) + ((__arx_v * (__arx_v + 1ULL)) & 1ULL));
    }
    __VISA_DISP_CTRL();
}
__h_vj: {
    unsigned int __jump_target = (%s >> 7) & 0x7FFFFU;
    /* Anti-Concolic Cryptographic ARX Path Trap (Vector 5) */
    unsigned long long __arx_v = (unsigned long long)%s;
    unsigned long long __arx_k = 0x517CC1B727220A95ULL;
    __arx_v += __arx_k;
    __arx_k = ((__arx_k << 13) | (__arx_k >> 51)) ^ __arx_v;
    __arx_v = ((__arx_v << 32) | (__arx_v >> 32)) + __arx_k;
    __arx_k = ((__arx_k << 16) | (__arx_k >> 48)) ^ __arx_v;
    %s = (unsigned int)((__jump_target) + ((__arx_v * (__arx_v + 1ULL)) & 1ULL));
    __VISA_DISP_CTRL();
}

__h_vjit: {
    /* Architecture A: Polymorphic In-VM Ephemeral AArch64 JIT Escape Gate */
    unsigned long long __a = __VREG_GET(%s), __b = __VREG_GET(%s);
    size_t __jit_sz = 0;
    static const uint32_t __vjit_enc_insns[%d] = { %s };
    const uint32_t __vjit_key = 0x%08lXU;
    size_t __jit_code_sz = sizeof(__vjit_enc_insns);
    unsigned char *__jpage = (unsigned char *)%s(&__jit_sz, __jit_code_sz);
    if (__jpage) {
#if defined(__APPLE__) && (defined(__aarch64__) || defined(__arm64__))
        pthread_jit_write_protect_np(0);
#endif
        for (size_t __i = 0; __i < sizeof(__vjit_enc_insns)/sizeof(uint32_t); ++__i) {
            ((uint32_t *)__jpage)[__i] = __vjit_enc_insns[__i] ^ __vjit_key;
        }
#if defined(__APPLE__) && (defined(__aarch64__) || defined(__arm64__))
        pthread_jit_write_protect_np(1);
#endif
#if defined(__aarch64__) || defined(__arm64__)
        /* Vector 15: Hardware-Direct In-Line Instruction Cache Invalidation (PoU) */
        {
            uintptr_t __line_addr = (uintptr_t)__jpage;
            uintptr_t __end_addr  = __line_addr + __jit_code_sz;
            for (uintptr_t __p = __line_addr; __p < __end_addr; __p += 64) {
                __asm__ volatile("dc cvau, %%0" : : "r"(__p) : "memory");
            }
            __asm__ volatile("dsb ish" : : : "memory");
            for (uintptr_t __p = __line_addr; __p < __end_addr; __p += 64) {
                __asm__ volatile("ic ivau, %%0" : : "r"(__p) : "memory");
            }
            __asm__ volatile("dsb ish\n\tisb" : : : "memory");
        }
#endif
        typedef unsigned long long (*__vjit_fn_t)(unsigned long long, unsigned long long);
        volatile __vjit_fn_t __jfn = (__vjit_fn_t)(void *)__jpage;
        unsigned long long __jres = __jfn(__a, __b);
        %s(__jpage, __jit_sz);
        __VREG_SET(%s, __jres);
    } else {
        __VREG_SET(%s, ((__a ^ __b) * %dULL) + %dULL);
    }
    __VISA_DISP_JIT();
}
__h_vjit_alt1: {
    /* Architecture A: Polymorphic In-VM Ephemeral AArch64 JIT Escape Gate (Alt Alias) */
    unsigned long long __a = __VREG_GET(%s), __b = __VREG_GET(%s);
    size_t __jit_sz = 0;
    static const uint32_t __vjit_alt1_enc_insns[%d] = { %s };
    const uint32_t __vjit_alt1_key = 0x%08lXU;
    size_t __jit_code_sz = sizeof(__vjit_alt1_enc_insns);
    unsigned char *__jpage = (unsigned char *)%s(&__jit_sz, __jit_code_sz);
    if (__jpage) {
#if defined(__APPLE__) && (defined(__aarch64__) || defined(__arm64__))
        pthread_jit_write_protect_np(0);
#endif
        for (size_t __i = 0; __i < sizeof(__vjit_alt1_enc_insns)/sizeof(uint32_t); ++__i) {
            ((uint32_t *)__jpage)[__i] = __vjit_alt1_enc_insns[__i] ^ __vjit_alt1_key;
        }
#if defined(__APPLE__) && (defined(__aarch64__) || defined(__arm64__))
        pthread_jit_write_protect_np(1);
#endif
#if defined(__aarch64__) || defined(__arm64__)
        /* Vector 15: Hardware-Direct In-Line Instruction Cache Invalidation (PoU) */
        {
            uintptr_t __line_addr = (uintptr_t)__jpage;
            uintptr_t __end_addr  = __line_addr + __jit_code_sz;
            for (uintptr_t __p = __line_addr; __p < __end_addr; __p += 64) {
                __asm__ volatile("dc cvau, %%0" : : "r"(__p) : "memory");
            }
            __asm__ volatile("dsb ish" : : : "memory");
            for (uintptr_t __p = __line_addr; __p < __end_addr; __p += 64) {
                __asm__ volatile("ic ivau, %%0" : : "r"(__p) : "memory");
            }
            __asm__ volatile("dsb ish\n\tisb" : : : "memory");
        }
#endif

        typedef unsigned long long (*__vjit_fn_t)(unsigned long long, unsigned long long);
        volatile __vjit_fn_t __jfn = (__vjit_fn_t)(void *)__jpage;
        unsigned long long __jres = __jfn(__a, __b);
        %s(__jpage, __jit_sz);
        __VREG_SET(%s, __jres);
    } else {
        __VREG_SET(%s, ((__a + __b) ^ 0x%XULL) * %dULL);
    }
    __VISA_DISP_JIT();
}


__h_default:
    __builtin_trap();
|}
  (* vadd *)
  vs.vs1 vs.vs2 f_vadd d1
  vs.vs1 vs.vs2 f_vadd1 d2
  vs.vs1 vs.vs2 f_vadd2 d3
  (decoy_stmt ())
  (* vsub *)
  vs.vs1 vs.vs2 f_vsub d4
  vs.vs1 vs.vs2 f_vsub1 d5
  vs.vs1 vs.vs2 f_vsub2 d6
  (decoy_stmt ())

  (* vmul *)
  vs.vs1 vs.vs2 f_vmul
  vs.vs1 vs.vs2 f_vmul1
  (decoy_stmt ())
  (* vxor *)
  vs.vs1 vs.vs2 f_vxor
  vs.vs1 vs.vs2 f_vxor1
  vs.vs1 vs.vs2 f_vxor2
  (decoy_stmt ())
  (* vand *)
  vs.vs1 vs.vs2 f_vand
  vs.vs1 vs.vs2 f_vand1
  (decoy_stmt ())
  (* vor *)
  vs.vs1 vs.vs2 f_vor
  vs.vs1 vs.vs2 f_vor1
  (* vsll *)
  vs.vs1 vs.vs2 vs.vd
  (* vsrl *)
  vs.vs1 vs.vs2 vs.vd
  (* vli *)
  vs.vd vs.vm vs.f3 vs.vs1 vs.vs2
  (* vli_alt1 — note extra paren in original: keep semantics *)
  vs.vd vs.vm vs.f3 vs.vs1 vs.vs2
  (* vmv *)
  vs.vd vs.vs1
  (* vmv_alt1 *)
  vs.vd vs.vs1
  (* vle8 *)
  vs.vs1 vs.vd vs.vs2
  (* vse8 *)
  vs.vpd (vs.dss - 1) vs.vsd vs.vpd vs.vs1
  (* vbge *)
  branch_target_line vs.vma vs.vs1 vs.vs2 vs.pc
  (* vj *)
  vs.ins vs.vma vs.pc

  (* vjit *)
  vs.vs1 vs.vs2
  len1 enc_insns1_str key1
  vs.alloc_fn vs.free_fn
  vs.vd vs.vd k1 k2
  (* vjit_alt1 *)
  vs.vs1 vs.vs2
  len2 enc_insns2_str key2
  vs.alloc_fn vs.free_fn
  vs.vd vs.vd k3 k4


