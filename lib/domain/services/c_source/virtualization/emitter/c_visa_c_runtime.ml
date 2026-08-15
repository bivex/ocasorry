(** Domain Service: C11 Runtime Kernel, Register Bank Matrix and CFI State Emitter *)

let emit_header
    ~(ret_type_str : string)
    ~(fn_name : string)
    ~(fn_params : string)
    ~(sbox_code : string) : string =
  Printf.sprintf {|
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

__attribute__((visibility("default")))
%s %s(%s) {
%s|} ret_type_str fn_name fn_params sbox_code

let emit_vbank
    ~(vreg_total : int)
    ~(vreg_rot_seed : int)
    ~(reg_mask_base : int64)
    ~(reg_mask_step : int64) : string =
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

let emit_shadow_and_cfi
    ~(word_count : int)
    ~(vbc_name : string)
    ~(ptr_arg : string)
    ~(reg_mask_base : int64)
    ~(reg_mask_step : int64)
    ~(arg_inits : string) : string =
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

let emit_epilogue
    ~(out_reg : int)
    ~(ret_type_str : string)
    ~(reg_mask_step : int64) : string =
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
