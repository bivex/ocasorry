/* ==============================================================================
 * Formal Sail Specification: VCPU 2 (2-Tier Nested Hierarchical Interpreter)
 * Architecture: NestedVM_Hierarchical_Arch
 * ============================================================================== */

default Order dec
$include <prelude.sail>

type inner_reg_idx = range(0, 7)

/* Inner Worker Register File & Execution State */
register Inner_R : vector(8, dec, bits(32))
register Outer_PC : bits(32)
register Inner_PC : bits(32)
register Inner_Key : bits(8)
register VM_Result : bits(32)

/* Outer Meta-Controller Instruction AST */
union outer_ast = {
    OUT_SETUP      : unit,
    OUT_DISPATCH   : unit,
    OUT_MUTATE_KEY : bits(8),
    OUT_HALT       : unit
}

/* Inner Worker VCPU Instruction AST */
union inner_ast = {
    IN_NOP        : unit,
    IN_LOAD_ARG   : (inner_reg_idx, bits(8)),
    IN_LOAD_CONST : (inner_reg_idx, bits(32)),
    IN_ADD        : (inner_reg_idx, inner_reg_idx, inner_reg_idx),
    IN_SUB        : (inner_reg_idx, inner_reg_idx, inner_reg_idx),
    IN_XOR        : (inner_reg_idx, inner_reg_idx, inner_reg_idx),
    IN_MUL        : (inner_reg_idx, inner_reg_idx, inner_reg_idx),
    IN_RET        : (inner_reg_idx)
}

function decode_outer(op : bits(8)) -> option(outer_ast) = {
    match unsigned(op) {
        0x10 => Some(OUT_SETUP()),
        0x30 => Some(OUT_DISPATCH()),
        0x20 => Some(OUT_MUTATE_KEY(0x1F)),
        0xFF => Some(OUT_HALT()),
        _    => None()
    }
}

function decode_inner(op : bits(8), a1 : bits(8), a2 : bits(8), a3 : bits(8)) -> option(inner_ast) = {
    match unsigned(op) {
        0x00 => Some(IN_NOP()),
        0x01 => Some(IN_LOAD_ARG(unsigned(a2[2..0]), a1)),
        0x02 => Some(IN_LOAD_CONST(unsigned(a2[2..0]), EXTZ(a1))),
        0x03 => Some(IN_ADD(unsigned(a1[2..0]), unsigned(a2[2..0]), unsigned(a3[2..0]))),
        0x04 => Some(IN_SUB(unsigned(a1[2..0]), unsigned(a2[2..0]), unsigned(a3[2..0]))),
        0x05 => Some(IN_XOR(unsigned(a1[2..0]), unsigned(a2[2..0]), unsigned(a3[2..0]))),
        0x06 => Some(IN_MUL(unsigned(a1[2..0]), unsigned(a2[2..0]), unsigned(a3[2..0]))),
        0x0F => Some(IN_RET(unsigned(a1[2..0]))),
        _    => None()
    }
}

function execute_inner(inst : inner_ast) -> bool = {
    match inst {
        IN_NOP()                   => true,
        IN_LOAD_ARG(dst, arg_idx)  => true,
        IN_LOAD_CONST(dst, imm)    => { Inner_R[dst] = imm; true },
        IN_ADD(dst, s1, s2)        => { Inner_R[dst] = Inner_R[s1] + Inner_R[s2]; true },
        IN_SUB(dst, s1, s2)        => { Inner_R[dst] = Inner_R[s1] - Inner_R[s2]; true },
        IN_XOR(dst, s1, s2)        => { Inner_R[dst] = Inner_R[s1] ^ Inner_R[s2]; true },
        IN_MUL(dst, s1, s2)        => { Inner_R[dst] = Inner_R[s1] * Inner_R[s2]; true },
        IN_RET(src)                => { VM_Result = Inner_R[src]; false }
    }
}
