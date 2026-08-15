open C_visa_spec

(** C11 Direct-Threaded Emulator Body Code Generator with Entangled Register Masking *)
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
    ~(word_count : int)
    ~(vbc_name : string)
    ~(pack_key : int64)
    ~(delta_key : int64)
    ~(lay : visa_field_layout) : string =
  Format.sprintf {|
#include <stdint.h>
#include <string.h>

__attribute__((visibility("default")))
%s %s(%s) {
    unsigned long long __vregs[%d];
    #define __VREG_MASK(r) (0x%LxULL + ((unsigned long long)(r) * 0x%LxULL))
    #define __VREG_GET(r) (__vregs[(r)] ^ __VREG_MASK(r))
    #define __VREG_SET(r, val) do { __vregs[(r)] = ((unsigned long long)(val)) ^ __VREG_MASK(r); } while(0)

    for (int __i = 0; __i < %d; __i++) {
        __vregs[__i] = __VREG_MASK(__i);
    }
%s
    const char *__ptr_ctx = (const char *)%s;
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
        goto *__dispatch_table[__funct6 & 0x3F]; \
    } while (0)

    /* Enter Direct Threading pipeline */
    __VISA_DISPATCH();

__h_vadd:
    __VREG_SET(__vd, __VREG_GET(__vs1) + __VREG_GET(__vs2));
    __VISA_DISPATCH();

__h_vsub:
    __VREG_SET(__vd, __VREG_GET(__vs1) - __VREG_GET(__vs2));
    __VISA_DISPATCH();

__h_vmul:
    __VREG_SET(__vd, __VREG_GET(__vs1) * __VREG_GET(__vs2));
    __VISA_DISPATCH();

__h_vxor:
    __VREG_SET(__vd, __VREG_GET(__vs1) ^ __VREG_GET(__vs2));
    __VISA_DISPATCH();

__h_vand:
    __VREG_SET(__vd, __VREG_GET(__vs1) & __VREG_GET(__vs2));
    __VISA_DISPATCH();

__h_vor:
    __VREG_SET(__vd, __VREG_GET(__vs1) | __VREG_GET(__vs2));
    __VISA_DISPATCH();

__h_vsll:
    __VREG_SET(__vd, __VREG_GET(__vs1) << __VREG_GET(__vs2));
    __VISA_DISPATCH();

__h_vsrl:
    __VREG_SET(__vd, (unsigned long long)(__VREG_GET(__vs1) >> __VREG_GET(__vs2)));
    __VISA_DISPATCH();

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
    unsigned long long __res_val = __VREG_GET(0);
    __builtin_memset(__vregs, 0, sizeof(__vregs));
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
    arg_inits
    ptr_arg
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
    ret_type_str
