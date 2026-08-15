/* ==============================================================================
 * Formal Sail Specification for Synthesized Architecture: vISA_License_Cascade_Arch
 * Generated automatically by OcaSorry random_vISA Synthesizer
 * ============================================================================== */

default Order dec

$include <prelude.sail>
$include <string.sail>

type xlen : Int = 32
type reg_index = range(0, 15)

/* Register File */
register R : vector(16, dec, bits(32))
register PC : bits(32)

/* Instruction Union */
union ast = {
    VADD_VV : (reg_index, reg_index, reg_index),
    VSUB_VV : (reg_index, reg_index, reg_index),
    VMUL_VV : (reg_index, reg_index, reg_index),
    VXOR_VV : (reg_index, reg_index, reg_index),
    VAND_VV : (reg_index, reg_index, reg_index),
    VOR_VV  : (reg_index, reg_index, reg_index),
    VSLL_VV : (reg_index, reg_index, reg_index),
    VSRL_VV : (reg_index, reg_index, reg_index),
    VLI_VI  : (reg_index, bits(10)),
    VMV_VV  : (reg_index, reg_index),
    VLE8_V  : (reg_index, reg_index),
    VRET_V  : (reg_index),
    VBGE_VV : (reg_index, reg_index),
    VJ      : (bits(32))
}

/* Decode Clause mapping 32-bit words to AST */
function decode(inst : bits(32)) -> option(ast) = {
    let funct6 : bits(6) = inst[31..26];
    let vs2    : reg_index = unsigned(inst[24..20]);
    let vs1    : reg_index = unsigned(inst[19..15]);
    let vd     : reg_index = unsigned(inst[11..7]);
    let imm10  : bits(10)  = inst[24..15];

    match unsigned(funct6) {
        6 => Some(VADD_VV(vd, vs1, vs2)),
        59 => Some(VSUB_VV(vd, vs1, vs2)),
        62 => Some(VMUL_VV(vd, vs1, vs2)),
        35 => Some(VXOR_VV(vd, vs1, vs2)),
        18 => Some(VAND_VV(vd, vs1, vs2)),
        38  => Some(VOR_VV(vd, vs1, vs2)),
        22 => Some(VSLL_VV(vd, vs1, vs2)),
        30 => Some(VSRL_VV(vd, vs1, vs2)),
        9  => Some(VLI_VI(vd, imm10)),
        47  => Some(VMV_VV(vd, vs1)),
        54  => Some(VLE8_V(vd, vs2)),
        16  => Some(VRET_V(vd)),
        43 => Some(VBGE_VV(vs1, vs2)),
        41      => Some(VJ(inst)),
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
        VLI_VI(vd, imm)       => R[vd] = EXTS(imm),
        VMV_VV(vd, vs1)       => R[vd] = R[vs1],
        VLE8_V(vd, vs2)       => (),
        VRET_V(vd)            => (),
        VBGE_VV(vs1, vs2)     => (),
        VJ(target)            => ()
    }
}
