open C_visa_spec

(** C11 Direct-Threaded Emulator Body Code Generator with:
    - Entangled Register Masking (Vector 3)
    - Dual Shadow Stack & Dynamic CFI Canary (Vector 2)
*)
let emit_function_body
    ~(ret_type_str : string)
    ~(fn_name : string)
    ~(fn_params : string)
    ~(vreg_total : int)
    ~(reg_mask_base : int64)
    ~(reg_mask_step : int64)
    ~(arg_inits : string)
    ~(ptr_arg : string)
    ~(op : visa_opcodes)
    ~(out_reg : int)
    ~(word_count : int)
    ~(vbc_name : string)
    ~(pack_key : int64)
    ~(delta_key : int64)
    ~(lay : visa_field_layout) : string =
  let cfi_seed = Int64.logand (Int64.abs reg_mask_base) 0xFFFFFFFFFFFFL in
  let cfi_xor = Int64.logxor reg_mask_step 0xDEADBEEFCAFEBABEL in
  Format.sprintf {|
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

__attribute__((visibility("default")))
%s %s(%s) {
    unsigned long long __vregs[%d];
    #define __VREG_MASK(r) (0x%LxULL + ((unsigned long long)(r) * 0x%LxULL))
    #define __VREG_GET(r) (__vregs[(r)] ^ __VREG_MASK(r))
    #define __VREG_SET(r, val) do { __vregs[(r)] = ((unsigned long long)(val)) ^ __VREG_MASK(r); } while(0)

    for (int __i = 0; __i < %d; __i++) {
        __vregs[__i] = __VREG_MASK(__i);
    }

    /* Vector 2: Dual Shadow Stack (VSP_data + VSP_ctrl) */
    unsigned long long __vstack_data[64] = {0};
    unsigned long long __vstack_ctrl[32] = {0};
    unsigned int __vsp_d = 0;
    unsigned int __vsp_c = 0;
    unsigned long long __vm_state_acc = 0x9E3779B97F4A7C15ULL;

    const char *__ptr_ctx = (const char *)%s;
    const unsigned long long __cfi_canary = 0x%LxULL ^ ((uintptr_t)__ptr_ctx * 0x9E3779B97F4A7C15ULL);

    /* Push CFI Canary into Shadow Control Stack */
    __vstack_ctrl[__vsp_c++] = __cfi_canary ^ 0x%LxULL;

%s
    unsigned int __pc = 0;
    unsigned int __raw, __key, __inst;
    unsigned char __funct6, __vm, __vs2, __vs1, __funct3, __vd;

    /* Direct Threading Dispatch Table via GNU C Computed Gotos */
    static const void * const __dispatch_table[64] = {
        [0 ... 63] = &&__h_default,
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
        [0x%X] = &&__h_vj
    };

    #define __VISA_DISPATCH() do { \
        if (__pc >= %d) goto __h_vret; \
        __raw = %s[__pc]; \
        __key = 0x%LxU ^ (__pc * 0x%LxU); \
        __inst = __raw ^ __key; \
        __funct6 = (unsigned char)((__inst >> %d) & 0x%X); \
        __vm     = (unsigned char)((__inst >> %d) & 0x01); \
        __vs2    = (unsigned char)((__inst >> %d) & 0x1F); \
        __vs1    = (unsigned char)((__inst >> %d) & 0x1F); \
        __funct3 = (unsigned char)((__inst >> %d) & 0x07); \
        __vd     = (unsigned char)((__inst >> %d)  & 0x1F); \
        __pc++; \
        __vm_state_acc = (__vm_state_acc ^ (__vd + __funct6)) * 0x517CC1B727220A95ULL; \
        goto *__dispatch_table[__funct6 & 0x3F]; \
    } while (0)

    /* Enter Direct Threading pipeline */
    __VISA_DISPATCH();

__h_vadd: {
    unsigned long long __a = __VREG_GET(__vs1), __b = __VREG_GET(__vs2);
    /* Non-Linear MBA ADD: (a ^ b) + ((a & b) << 1) */
    __VREG_SET(__vd, (__a ^ __b) + ((__a & __b) << 1));
    __VISA_DISPATCH();
}

__h_vsub: {
    unsigned long long __a = __VREG_GET(__vs1), __b = __VREG_GET(__vs2);
    /* Non-Linear MBA SUB: (a ^ b) - ((~a & b) << 1) */
    __VREG_SET(__vd, (__a ^ __b) - ((~__a & __b) << 1));
    __VISA_DISPATCH();
}

__h_vmul: {
    unsigned long long __a = __VREG_GET(__vs1), __b = __VREG_GET(__vs2);
    /* 64-bit Decomposed Karatsuba Multiplier */
    unsigned long long __al = __a & 0xFFFFFFFFULL, __ah = __a >> 32;
    unsigned long long __bl = __b & 0xFFFFFFFFULL, __bh = __b >> 32;
    unsigned long long __p0 = __al * __bl;
    unsigned long long __p1 = (__al * __bh) + (__ah * __bl);
    __VREG_SET(__vd, __p0 + (__p1 << 32));
    __VISA_DISPATCH();
}

__h_vxor: {
    unsigned long long __a = __VREG_GET(__vs1), __b = __VREG_GET(__vs2);
    /* Non-Linear MBA XOR: (a | b) - (a & b) */
    __VREG_SET(__vd, (__a | __b) - (__a & __b));
    __VISA_DISPATCH();
}

__h_vand: {
    unsigned long long __a = __VREG_GET(__vs1), __b = __VREG_GET(__vs2);
    /* Non-Linear MBA AND: (a | b) - (a ^ b) */
    __VREG_SET(__vd, (__a | __b) - (__a ^ __b));
    __VISA_DISPATCH();
}

__h_vor: {
    unsigned long long __a = __VREG_GET(__vs1), __b = __VREG_GET(__vs2);
    /* Non-Linear MBA OR: (a & b) + (a ^ b) */
    __VREG_SET(__vd, (__a & __b) + (__a ^ __b));
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

__h_vmv:
    __VREG_SET(__vd, __VREG_GET(__vs1));
    __VISA_DISPATCH();

__h_vle8:
    if (__ptr_ctx) {
        __VREG_SET(__vd, (unsigned long long)((const unsigned char *)__ptr_ctx)[__VREG_GET(__vs2)]);
    }
    __VISA_DISPATCH();

__h_vse8:
    if (__vsp_d < 63) {
        __vstack_data[__vsp_d++] = __VREG_GET(__vs1);
    }
    __VISA_DISPATCH();

__h_vbge:
    if (__VREG_GET(__vs1) >= __VREG_GET(__vs2)) {
        __pc = (%d);
    }
    __VISA_DISPATCH();

__h_vj:
    __pc = ((__inst >> 7) & 0x7FFFF);
    __VISA_DISPATCH();

__h_default:
    __VISA_DISPATCH();

__h_vret: ;
    /* Verify Shadow Control Stack CFI Canary */
    if (__vsp_c == 0 || ((__vstack_ctrl[--__vsp_c] ^ 0x%LxULL) != __cfi_canary)) {
        __builtin_trap();
    }
    unsigned long long __res_val = __VREG_GET(%d);
    __builtin_memset(__vregs, 0, sizeof(__vregs));
    __builtin_memset(__vstack_data, 0, sizeof(__vstack_data));
    __builtin_memset(__vstack_ctrl, 0, sizeof(__vstack_ctrl));
    return (%s)__res_val;
}
|}
    ret_type_str
    fn_name
    fn_params
    vreg_total
    reg_mask_base
    reg_mask_step
    vreg_total
    ptr_arg
    cfi_seed
    cfi_xor
    arg_inits
    op.vadd_vv
    op.vsub_vv
    op.vmul_vv
    op.vxor_vv
    op.vand_vv
    op.vor_vv
    op.vsll_vv
    op.vsrl_vv
    op.vli_vi
    op.vmv_vv
    op.vle8_v
    op.vse8_v
    op.vret_v
    op.vbge_vv
    op.vj
    word_count
    vbc_name
    pack_key
    delta_key
    lay.funct6_shift lay.funct6_mask
    lay.vm_shift
    lay.vs2_shift
    lay.vs1_shift
    lay.funct3_shift
    lay.vd_shift
    (word_count - 2)
    cfi_xor
    out_reg
    ret_type_str

