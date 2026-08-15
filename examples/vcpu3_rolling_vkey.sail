/* ==============================================================================
 * Formal Sail Specification: VCPU 3 (Stateful Rolling Key Virtual Machine)
 * Architecture: RollingVKey_Stateful_Arch
 * ============================================================================== */

default Order dec
$include <prelude.sail>

type r_reg_idx = range(0, 3)
register Regs : vector(4, dec, bits(32))
register VKey : bits(32)
register PC : bits(32)

union rolling_ast = {
    R_ADD_IMM : (r_reg_idx, r_reg_idx, bits(32)),
    R_XOR_IMM : (r_reg_idx, r_reg_idx, bits(32)),
    R_MUL_IMM : (r_reg_idx, r_reg_idx, bits(32)),
    R_HALT    : (r_reg_idx)
}

function evolve_vkey(vkey : bits(32), dec_word : bits(32)) -> bits(32) = {
    let term : bits(32) = dec_word + 0x9E3779B9;
    (vkey * 33) ^ term
}

function decode_rolling(op : bits(8)) -> option(rolling_ast) = {
    match unsigned(op) {
        0x01 => Some(R_ADD_IMM(1, 0, EXTZ(0x0A))),
        0x02 => Some(R_XOR_IMM(2, 1, EXTZ(0x2A))),
        0x03 => Some(R_MUL_IMM(3, 2, EXTZ(0x02))),
        0xFF => Some(R_HALT(3)),
        _    => None()
    }
}

function execute_rolling(inst : rolling_ast) -> bool = {
    match inst {
        R_ADD_IMM(dst, src, imm) => { Regs[dst] = Regs[src] + imm; true },
        R_XOR_IMM(dst, src, imm) => { Regs[dst] = Regs[src] ^ imm; true },
        R_MUL_IMM(dst, src, imm) => { Regs[dst] = Regs[src] * imm; true },
        R_HALT(src)              => false
    }
}
