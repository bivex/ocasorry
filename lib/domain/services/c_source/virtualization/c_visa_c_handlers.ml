(** Domain Service: C11 Opcode Handlers Generator for vISA Virtual Machines
    Generates C11 code for all ALU, bitwise, memory load/store, and branching operations.
*)

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
