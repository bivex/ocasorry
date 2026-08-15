open C_visa_spec

(** Domain Service: C11 Direct-Threaded Emulator Kernel Emitter
    Modular decomposition:
    1. Header & Function Signature with S-Box LUTs
    2. Overlapping Aliased Register Bank Matrix (__vbank)
    3. Dual Shadow Stacks & Dynamic CFI Canary Synthesis
    4. Direct-Threading Computed-Goto Dispatch Table & Synthetic S-Box Traps
    5. Synchronized Stream Decryption & Dispatch Macro (__VISA_DISPATCH)
    6. Polymorphic Arithmetic, Bitwise, Load/Store & Control Flow Opcode Handlers
    7. Microarchitectural Anti-Stepping, Zero-Wipe Epilogue & Macro Isolation (#undef)
*)

let emit_header ~(ret_type_str : string) ~(fn_name : string) ~(fn_params : string) ~(sbox_code : string) : string =
  Printf.sprintf {|
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

__attribute__((visibility("default")))
%s %s(%s) {
%s|} ret_type_str fn_name fn_params sbox_code

let emit_vbank ~(vreg_total : int) ~(vreg_rot_seed : int) ~(reg_mask_base : int64) ~(reg_mask_step : int64) : string =
  Printf.sprintf {|
    /* Anti-VTIL / Anti-NoVmp: Overlapping Aliased VCPU Register Matrix */
    union __attribute__((aligned(16))) {
        unsigned char __b[1024];
        unsigned long long __q[%d];
    } __vbank;
    #define __VREG_ROT(r) (((unsigned int)(r) + %uU) & 0x3FU)
    #define __VREG_MASK(r) (0x%LxULL + ((unsigned long long)__VREG_ROT(r) * 0x%LxULL))
    #define __VREG_GET(r) (__vbank.__q[__VREG_ROT(r)] ^ __VREG_MASK(r))
    #define __VREG_SET(r, val) do { __vbank.__q[__VREG_ROT(r)] = ((unsigned long long)(val)) ^ __VREG_MASK(r); } while(0)

    for (int __i = 0; __i < %d; __i++) {
        __vbank.__q[__i] = (0x%LxULL + ((unsigned long long)__i * 0x%LxULL));
    }
|} vreg_total vreg_rot_seed reg_mask_base reg_mask_step vreg_total reg_mask_base reg_mask_step

let emit_shadow_and_cfi ~(word_count : int) ~(vbc_name : string) ~(ptr_arg : string) ~(reg_mask_base : int64) ~(reg_mask_step : int64) ~(arg_inits : string) : string =
  let cfi_seed = Int64.logand (Int64.abs reg_mask_base) 0xFFFFFFFFFFFFL in
  let cfi_xor = Int64.logxor reg_mask_step 0xDEADBEEFCAFEBABEL in
  let hash_idx = if word_count > 1 then 1 else 0 in
  Printf.sprintf {|
    /* Vector 2: Dual Shadow Stack (VSP_data + VSP_ctrl) */
    unsigned long long __vstack_data[64] = {0};
    unsigned long long __vstack_ctrl[32] = {0};
    unsigned int __vsp_d = 0;
    unsigned int __vsp_c = 0;
    unsigned long long __vm_state_acc = 0x9E3779B97F4A7C15ULL;

    /* Vector 12: Microarchitectural Timer Sampling & Anti-Single-Stepping */
    #if defined(__aarch64__)
    unsigned long long __t_entry;
    __asm__ volatile("mrs %%0, cntvct_el0" : "=r"(__t_entry));
    #elif defined(__x86_64__)
    unsigned int __t_lo, __t_hi;
    __asm__ volatile("rdtsc" : "=a"(__t_lo), "=d"(__t_hi));
    unsigned long long __t_entry = ((unsigned long long)__t_hi << 32) | __t_lo;
    #else
    unsigned long long __t_entry = 0;
    #endif

    /* Vector 8: Ephemeral Self-Scrubbing Bytecode Scratchpad */
    unsigned int __vbc_live[%d];
    memcpy(__vbc_live, %s, sizeof(__vbc_live));

    const unsigned long long __fn_addr_entropy =
        (unsigned long long)(uintptr_t)(%s != 0 ? (const void *)%s : (const void *)&__vbc_live);
    const unsigned long long __vbc_hash_0 = __vbc_live[0] ^ (unsigned long long)__vbc_live[%d];
    const unsigned long long __cfi_canary =
        0x%LxULL
        ^ (__fn_addr_entropy * 0x9E3779B97F4A7C15ULL)
        ^ (__vbc_hash_0 * 0x517CC1B727220A95ULL);

    __vstack_ctrl[__vsp_c++] = __cfi_canary ^ 0x%LxULL;

%s
    unsigned int __pc = 0;
    unsigned int __raw, __key, __inst;
    unsigned char __funct6, __vm, __vs2, __vs1, __funct3, __vd;
|} word_count vbc_name ptr_arg ptr_arg hash_idx cfi_seed cfi_xor arg_inits

let emit_dispatch_table ~(op : visa_opcodes) ~(prof : C_visa_profile_service.vm_profile_config) ~(trap_bindings_str : string) : string =
  let size = prof.dispatch_size in
  Printf.sprintf {|
    /* Direct Threading Dispatch Table via GNU C Computed Gotos */
    static const void * const __dispatch_table[%d] = {
        [0 ... %d] = &&__h_default,
        [0x%X] = &&__h_vadd,
        [0x%X] = &&__h_vsub,
        [0x%X] = &&__h_vmul,
        [0x%X] = &&__h_vxor,
        [0x%X] = &&__h_vand,
        [0x%X] = &&__h_vor,
        [0x%X] = &&__h_vsll,
        [0x%X] = &&__h_vsrl,
        [0x%X] = &&__h_vli,
        [0x%X] = &&__h_vmv,
        [0x%X] = &&__h_vle8,
        [0x%X] = &&__h_vse8,
        [0x%X] = &&__h_vret,
        [0x%X] = &&__h_vbge,
        [0x%X] = &&__h_vj,
        /* Polymorphic Multi-Alias Opcode Handlers */
        [0x%X] = &&__h_vadd_alt1,
        [0x%X] = &&__h_vadd_alt2,
        [0x%X] = &&__h_vsub_alt1,
        [0x%X] = &&__h_vsub_alt2,
        [0x%X] = &&__h_vxor_alt1,
        [0x%X] = &&__h_vxor_alt2,
        [0x%X] = &&__h_vand_alt1,
        [0x%X] = &&__h_vor_alt1,
        [0x%X] = &&__h_vmul_alt1,
        [0x%X] = &&__h_vmv_alt1,
        [0x%X] = &&__h_vli_alt1,
%s
    };
|} size (size - 1)
   op.vadd_vv op.vsub_vv op.vmul_vv op.vxor_vv op.vand_vv op.vor_vv op.vsll_vv op.vsrl_vv
   op.vli_vi op.vmv_vv op.vle8_v op.vse8_v op.vret_v op.vbge_vv op.vj
   op.vadd_alt1 op.vadd_alt2 op.vsub_alt1 op.vsub_alt2 op.vxor_alt1 op.vxor_alt2
   op.vand_alt1 op.vor_alt1 op.vmul_alt1 op.vmv_alt1 op.vli_alt1
   trap_bindings_str

let emit_dispatch_macro ~(word_count : int) ~(affine_p : int) ~(affine_s : int) ~(pack_key : int64) ~(delta_key : int64) ~(lay : visa_field_layout) ~(prof : C_visa_profile_service.vm_profile_config) : string =
  let pk32 = Int64.to_int32 pack_key in
  let dk32 = Int64.to_int32 delta_key in
  let mask_size = prof.dispatch_size - 1 in
  Printf.sprintf {|
    #define __VISA_DISPATCH() do { \
        if (__pc >= %d) goto __h_vret; \
        unsigned int __slot = ((__pc * %uU) + %uU) %% %uU; \
        __raw = __vbc_live[__slot]; \
        __key = 0x%lXU ^ (__pc * 0x%lXU); \
        __inst = __raw ^ __key; \
        __funct6 = (unsigned char)((__inst >> %d) & 0x%X); \
        __vm     = (unsigned char)((__inst >> %d) & 0x01); \
        __vs2    = (unsigned char)((__inst >> %d) & 0x1F); \
        __vs1    = (unsigned char)((__inst >> %d) & 0x1F); \
        __funct3 = (unsigned char)((__inst >> %d) & 0x07); \
        __vd     = (unsigned char)((__inst >> %d)  & 0x1F); \
        __pc++; \
        __vm_state_acc = ((__vm_state_acc * 0x63c63cd93839c9b9ULL) ^ (__vd + __funct6 + (unsigned long long)__pc)) * 0x517CC1B727220A95ULL; \
        goto *__dispatch_table[__funct6 & 0x%X]; \
    } while (0)

    /* Enter Direct Threading pipeline */
    __VISA_DISPATCH();
|} word_count affine_p affine_s word_count pk32 dk32
   lay.funct6_shift lay.funct6_mask lay.vm_shift lay.vs2_shift lay.vs1_shift lay.funct3_shift lay.vd_shift mask_size

let emit_handlers ~(trap_code : string) : string =
  trap_code ^ {|
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
    unsigned int __branch_target = (__inst >> 7) & 0xFFU;
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
__h_default:
    __builtin_trap();
|}

let emit_epilogue ~(out_reg : int) ~(ret_type_str : string) ~(reg_mask_step : int64) : string =
  let cfi_xor = Int64.logxor reg_mask_step 0xDEADBEEFCAFEBABEL in
  Printf.sprintf {|
__h_vret: ;
    /* Verify Shadow Control Stack CFI Canary */
    if (__vsp_c == 0 || ((__vstack_ctrl[--__vsp_c] ^ 0x%LxULL) != __cfi_canary)) {
        __builtin_trap();
    }
    /* Vector 12: Microarchitectural Timer Check & Silent State Poisoning */
    #if defined(__aarch64__)
    unsigned long long __t_exit;
    __asm__ volatile("mrs %%0, cntvct_el0" : "=r"(__t_exit));
    #elif defined(__x86_64__)
    unsigned int __x_lo, __x_hi;
    __asm__ volatile("rdtsc" : "=a"(__x_lo), "=d"(__x_hi));
    unsigned long long __t_exit = ((unsigned long long)__x_hi << 32) | __x_lo;
    #else
    unsigned long long __t_exit = 0;
    #endif
    unsigned long long __t_delta = (__t_exit > __t_entry) ? (__t_exit - __t_entry) : 0ULL;
    unsigned long long __stepped = (__t_delta > 1000000000ULL) ? 1ULL : 0ULL;
    __vm_state_acc ^= (__stepped * 0x9E3779B97F4A7C15ULL);

    /* Vector 11: Anti-Symbolic Quadratic Invariant & Dataflow Interlock */
    if (((__vm_state_acc * (__vm_state_acc + 1ULL)) & 1ULL) != 0ULL) {
        __builtin_trap();
    }
    unsigned long long __res_val = (__VREG_GET(%d) ^ (__stepped * 0xBADF00DULL)) ^ ((__vm_state_acc * (__vm_state_acc + 1ULL)) & 1ULL);
    __builtin_memset(&__vbank, 0, sizeof(__vbank));
    __builtin_memset(__vbc_live, 0, sizeof(__vbc_live));
    __builtin_memset(__vstack_data, 0, sizeof(__vstack_data));
    __builtin_memset(__vstack_ctrl, 0, sizeof(__vstack_ctrl));
    return (%s)__res_val;
}
#undef __VREG_ROT
#undef __VREG_MASK
#undef __VREG_GET
#undef __VREG_SET
#undef __VISA_DISPATCH
|} cfi_xor out_reg ret_type_str

let emit_function_body
    ~(ret_type_str : string)
    ~(fn_name : string)
    ~(fn_params : string)
    ~(vreg_total : int)
    ~(vreg_rot_seed : int)
    ~(reg_mask_base : int64)
    ~(reg_mask_step : int64)
    ~(arg_inits : string)
    ~(ptr_arg : string)
    ~(op : visa_opcodes)
    ~(out_reg : int)
    ~(affine_p : int)
    ~(affine_s : int)
    ~(word_count : int)
    ~(vbc_name : string)
    ~(pack_key : int64)
    ~(delta_key : int64)
    ~(lay : visa_field_layout) : string =
  let prof = C_visa_profile_service.get_active_profile () in
  let sbox_code = C_visa_profile_service.generate_sbox_luts prof.lut_count in
  let (trap_code, trap_bindings) =
    C_visa_profile_service.generate_synthetic_trap_handlers
      ~start_slot:64
      ~total_slots:prof.dispatch_size
      ~lut_count:prof.lut_count
  in
  let trap_bindings_str = C_visa_profile_service.format_trap_bindings trap_bindings in

  String.concat "" [
    emit_header ~ret_type_str ~fn_name ~fn_params ~sbox_code;
    emit_vbank ~vreg_total ~vreg_rot_seed ~reg_mask_base ~reg_mask_step;
    emit_shadow_and_cfi ~word_count ~vbc_name ~ptr_arg ~reg_mask_base ~reg_mask_step ~arg_inits;
    emit_dispatch_table ~op ~prof ~trap_bindings_str;
    emit_dispatch_macro ~word_count ~affine_p ~affine_s ~pack_key ~delta_key ~lay ~prof;
    emit_handlers ~trap_code;
    emit_epilogue ~out_reg ~ret_type_str ~reg_mask_step;
  ]
