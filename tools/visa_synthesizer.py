#!/usr/bin/env python3
"""
tools/visa_synthesizer.py - Formal Random Vector ISA Synthesizer
Generates randomized Sail-compatible ISA specifications and JSON schemas for OcaSorry.

Outputs:
  - JSON Architecture Spec (.json) consumed directly by OcaSorry
  - Formal Sail Spec (.sail) describing types, registers, instruction formats, and execution rules
"""

import sys
import os
import json
import random
import argparse

def generate_random_visa(seed=None, name=None):
    if seed is not None:
        random.seed(seed)
    
    isa_id = random.randint(0x1000, 0xFFFF)
    isa_name = name or f"vISA_Arch_{isa_id:04X}"
    
    # 1. Randomized 32-bit Vector Instruction Layout
    base_opcode = random.choice([0x57, 0x0B, 0x2B, 0x7B, 0x37, 0x67])
    
    # Randomize unique 6-bit funct6 codes for each operation
    funct6_pool = list(range(0, 64))
    random.shuffle(funct6_pool)
    
    opcodes = {
        "vadd_vv": funct6_pool.pop(),
        "vsub_vv": funct6_pool.pop(),
        "vmul_vv": funct6_pool.pop(),
        "vxor_vv": funct6_pool.pop(),
        "vand_vv": funct6_pool.pop(),
        "vor_vv":  funct6_pool.pop(),
        "vsll_vv": funct6_pool.pop(),
        "vsrl_vv": funct6_pool.pop(),
        "vli_vi":  funct6_pool.pop(),
        "vmv_vv":  funct6_pool.pop(),
        "vle8_v":  funct6_pool.pop(),
        "vse8_v":  funct6_pool.pop(),
        "vret_v":  funct6_pool.pop(),
        "vbge_vv": funct6_pool.pop(),
        "vblt_vv": funct6_pool.pop(),
        "vbeq_vv": funct6_pool.pop(),
        "vbne_vv": funct6_pool.pop(),
        "vj":      funct6_pool.pop(),
    }
    
    # 2. Key evolution constants for bytecode packing
    pack_key = random.randint(0x10000000, 0xFFFFFFFF)
    delta_key = random.choice([0x1000193, 0x9E3779B9, 0x045D9F3B, 0x21F0AAAD])
    
    # 3. Register Configuration
    reg_count = 16
    
    spec = {
        "isa_name": isa_name,
        "isa_version": "1.0",
        "word_bits": 32,
        "reg_count": reg_count,
        "pack_key": pack_key,
        "delta_key": delta_key,
        "layout": {
            "funct6_shift": 26,
            "funct6_mask": 0x3F,
            "vm_shift": 25,
            "vs2_shift": 20,
            "vs1_shift": 15,
            "funct3_shift": 12,
            "vd_shift": 7,
            "opcode_val": base_opcode
        },
        "opcodes": opcodes
    }
    return spec

def export_sail_specification(spec):
    """Generates formal Sail specification code for the synthesized ISA."""
    name = spec["isa_name"]
    op = spec["opcodes"]
    
    sail_code = f"""/* ==============================================================================
 * Formal Sail Specification for Synthesized Architecture: {name}
 * Generated automatically by OcaSorry random_vISA Synthesizer
 * ============================================================================== */

default Order dec

$include <prelude.sail>
$include <string.sail>

type xlen : Int = 32
type reg_index = range(0, {spec["reg_count"] - 1})

/* Register File */
register R : vector({spec["reg_count"]}, dec, bits(32))
register PC : bits(32)

/* Instruction Union */
union ast = {{
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
}}

/* Decode Clause mapping 32-bit words to AST */
function decode(inst : bits(32)) -> option(ast) = {{
    let funct6 : bits(6) = inst[31..26];
    let vs2    : reg_index = unsigned(inst[24..20]);
    let vs1    : reg_index = unsigned(inst[19..15]);
    let vd     : reg_index = unsigned(inst[11..7]);
    let imm10  : bits(10)  = inst[24..15];

    match unsigned(funct6) {{
        {op["vadd_vv"]} => Some(VADD_VV(vd, vs1, vs2)),
        {op["vsub_vv"]} => Some(VSUB_VV(vd, vs1, vs2)),
        {op["vmul_vv"]} => Some(VMUL_VV(vd, vs1, vs2)),
        {op["vxor_vv"]} => Some(VXOR_VV(vd, vs1, vs2)),
        {op["vand_vv"]} => Some(VAND_VV(vd, vs1, vs2)),
        {op["vor_vv"]}  => Some(VOR_VV(vd, vs1, vs2)),
        {op["vsll_vv"]} => Some(VSLL_VV(vd, vs1, vs2)),
        {op["vsrl_vv"]} => Some(VSRL_VV(vd, vs1, vs2)),
        {op["vli_vi"]}  => Some(VLI_VI(vd, imm10)),
        {op["vmv_vv"]}  => Some(VMV_VV(vd, vs1)),
        {op["vle8_v"]}  => Some(VLE8_V(vd, vs2)),
        {op["vret_v"]}  => Some(VRET_V(vd)),
        {op["vbge_vv"]} => Some(VBGE_VV(vs1, vs2)),
        {op["vj"]}      => Some(VJ(inst)),
        _ => None()
    }}
}}

/* Execution Semantics */
function execute(instruction : ast) -> unit = {{
    match instruction {{
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
    }}
}}
"""
    return sail_code

def main():
    parser = argparse.ArgumentParser(description="OcaSorry Formal Random Vector ISA Synthesizer")
    parser.add_argument("-o", "--output-json", default="visa_spec.json", help="Path to output JSON ISA specification")
    parser.add_argument("-s", "--output-sail", default=None, help="Optional path to output formal Sail specification (.sail)")
    parser.add_argument("--seed", type=int, default=None, help="Deterministic random seed")
    parser.add_argument("--name", default=None, help="Custom ISA architecture name")
    
    args = parser.parse_args()
    
    spec = generate_random_visa(seed=args.seed, name=args.name)
    
    with open(args.output_json, "w") as f:
        json.dump(spec, f, indent=2)
    print(f"[+] Synthesized ISA JSON Spec -> {args.output_json} ({spec['isa_name']})")
    
    sail_path = args.output_sail or args.output_json.replace(".json", ".sail")
    if not sail_path.endswith(".sail"):
        sail_path += ".sail"
        
    sail_src = export_sail_specification(spec)
    with open(sail_path, "w") as f:
        f.write(sail_src)
    print(f"[+] Formal Sail Architecture Spec -> {sail_path}")

if __name__ == "__main__":
    main()
