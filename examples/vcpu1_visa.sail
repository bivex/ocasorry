/* ==============================================================================
 * Formal Sail Specification: VCPU 1 (random_vISA Vector Processor)
 * Architecture: vISA_License_Cascade_Arch
 * ============================================================================== */

default Order dec

$include <prelude.sail>
$include <string.sail>

type xlen : Int = 32
type reg_index = range(0, 15)

/* Register File & Program Counter */
register R : vector(16, dec, bits(32))
register PC : bits(32)

/* Vector Instruction AST Union */
union ast = {
    VADD_VV : (reg_index, reg_index, reg_index),
    VSUB_VV : (reg_index, reg_index, reg_index),
    VMUL_VV : (reg_index, reg_index, reg_index),
    VXOR_VV : (reg_index, reg_index, reg_index),
    VAND_VV : (reg_index, reg_index, reg_index),
    VOR_VV  : (reg_index, reg_index, reg_index),
    VSLL_VV : (reg_index, reg_index, reg_index),
    VSRL_VV : (reg_index, reg_index, reg_index),
    VLI_VI  : (reg_index, bits(14)),
    VMV_VV  : (reg_index, reg_index),
    VLE8_V  : (reg_index, reg_index),
    VSE8_V  : (reg_index, reg_index, reg_index),
    VRET_V  : (reg_index),
    VBGE_VV : (reg_index, reg_index),
    VJ      : (bits(32))
}

/* 32-bit Word Decoder */
function decode(inst : bits(32)) -> option(ast) = {
    let funct6 : bits(6) = inst[31..26];
    let vs2    : reg_index = unsigned(inst[24..20]);
    let vs1    : reg_index = unsigned(inst[19..15]);
    let vd     : reg_index = unsigned(inst[11..7]);
    let imm14  : bits(14)  = inst[25..12];

    match unsigned(funct6) {
        16 => Some(VADD_VV(vd, vs1, vs2)),
        14 => Some(VSUB_VV(vd, vs1, vs2)),
        61 => Some(VMUL_VV(vd, vs1, vs2)),
        2 => Some(VXOR_VV(vd, vs1, vs2)),
        34 => Some(VAND_VV(vd, vs1, vs2)),
        0  => Some(VOR_VV(vd, vs1, vs2)),
        10 => Some(VSLL_VV(vd, vs1, vs2)),
        25 => Some(VSRL_VV(vd, vs1, vs2)),
        58  => Some(VLI_VI(vd, imm14)),
        8  => Some(VMV_VV(vd, vs1)),
        32  => Some(VLE8_V(vd, vs2)),
        44  => Some(VRET_V(vd)),
        6 => Some(VBGE_VV(vs1, vs2)),
        29      => Some(VJ(inst)),
        _ => None()
    }
}

/* Execution Semantics */
function execute(instruction : ast) -> unit = {
    match instruction {
        VADD_VV(vd, vs1, vs2) => R[vd] = R[vs1] + R[vs2],
        VSUB_VV(vd, vs1, vs2) => R[vd] = R[vs1] - R[vs2],
        VMUL_VV(vd, vs1, vs2) => R[vd] = R[vs1] * R[vs2],
        VXOR_VV(vd, vs1, vs2) => R[vd] = R[vs1] ^ R[vs2],
        VAND_VV(vd, vs1, vs2) => R[vd] = R[vs1] & R[vs2],
        VOR_VV(vd, vs1, vs2)  => R[vd] = R[vs1] | R[vs2],
        VSLL_VV(vd, vs1, vs2) => R[vd] = R[vs1] << unsigned(R[vs2]),
        VSRL_VV(vd, vs1, vs2) => R[vd] = R[vs1] >> unsigned(R[vs2]),
        VLI_VI(vd, imm)       => R[vd] = EXTZ(imm),
        VMV_VV(vd, vs1)       => R[vd] = R[vs1],
        VLE8_V(vd, vs2)       => (),
        VSE8_V(vd, vs1, vs2)  => (),
        VRET_V(vd)            => (),
        VBGE_VV(vs1, vs2)     => (),
        VJ(target)            => ()
    }
}
