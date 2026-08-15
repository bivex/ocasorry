#!/usr/bin/env python3
"""
tools/visa_synthesizer.py - Formal Multi-VCPU & Sail Architecture Synthesizer
Synthesizes randomized formal Sail-compatible ISA specifications and JSON schemas for OcaSorry.

Supports all 4 Federated Virtual Machine Tiers:
  - VCPU 1: random_vISA (32-bit Vector Instruction Bytecode ISA)
  - VCPU 2: nested_vm (2-Tier Hierarchical Outer/Inner VM)
  - VCPU 3: rolling_vkey (Stateful Rolling Decryption Key VM)
  - VCPU 4: ephemeral_jit (In-Memory Ephemeral Unpacking & Secure Wiper VM)

Outputs:
  - JSON Architecture Specs (.json) consumed directly by OcaSorry
  - Formal Sail Specs (.sail) describing AST unions, decode clauses, and execute semantics
"""

import sys
import os
import json
import random
import argparse

# ==============================================================================
# VCPU 1: random_vISA (32-bit Vector ISA)
# ==============================================================================
def generate_random_visa(seed=None, name=None):
    if seed is not None:
        random.seed(seed)
    
    isa_id = random.randint(0x1000, 0xFFFF)
    isa_name = name or f"vISA_Vector_Arch_{isa_id:04X}"
    
    base_opcode = random.choice([0x57, 0x0B, 0x2B, 0x7B, 0x37, 0x67])
    
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
    
    pack_key = random.randint(0x10000000, 0xFFFFFFFF)
    delta_key = random.choice([0x1000193, 0x9E3779B9, 0x045D9F3B, 0x21F0AAAD])
    reg_count = 16
    
    spec = {
        "vcpu_tier": 1,
        "vcpu_type": "random_visa",
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

def export_sail_visa(spec):
    name = spec["isa_name"]
    op = spec["opcodes"]
    
    return f"""/* ==============================================================================
 * Formal Sail Specification: VCPU 1 (random_vISA Vector Processor)
 * Architecture: {name}
 * ============================================================================== */

default Order dec

$include <prelude.sail>
$include <string.sail>

type xlen : Int = 32
type reg_index = range(0, {spec["reg_count"] - 1})

/* Register File & Program Counter */
register R : vector({spec["reg_count"]}, dec, bits(32))
register PC : bits(32)

/* Vector Instruction AST Union */
union ast = {{
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
}}

/* 32-bit Word Decoder */
function decode(inst : bits(32)) -> option(ast) = {{
    let funct6 : bits(6) = inst[31..26];
    let vs2    : reg_index = unsigned(inst[24..20]);
    let vs1    : reg_index = unsigned(inst[19..15]);
    let vd     : reg_index = unsigned(inst[11..7]);
    let imm14  : bits(14)  = inst[25..12];

    match unsigned(funct6) {{
        {op["vadd_vv"]} => Some(VADD_VV(vd, vs1, vs2)),
        {op["vsub_vv"]} => Some(VSUB_VV(vd, vs1, vs2)),
        {op["vmul_vv"]} => Some(VMUL_VV(vd, vs1, vs2)),
        {op["vxor_vv"]} => Some(VXOR_VV(vd, vs1, vs2)),
        {op["vand_vv"]} => Some(VAND_VV(vd, vs1, vs2)),
        {op["vor_vv"]}  => Some(VOR_VV(vd, vs1, vs2)),
        {op["vsll_vv"]} => Some(VSLL_VV(vd, vs1, vs2)),
        {op["vsrl_vv"]} => Some(VSRL_VV(vd, vs1, vs2)),
        {op["vli_vi"]}  => Some(VLI_VI(vd, imm14)),
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
        VLI_VI(vd, imm)       => R[vd] = EXTZ(imm),
        VMV_VV(vd, vs1)       => R[vd] = R[vs1],
        VLE8_V(vd, vs2)       => (),
        VSE8_V(vd, vs1, vs2)  => (),
        VRET_V(vd)            => (),
        VBGE_VV(vs1, vs2)     => (),
        VJ(target)            => ()
    }}
}}
"""

# ==============================================================================
# VCPU 2: nested_vm (2-Tier Hierarchical Nested VM)
# ==============================================================================
def generate_nested_vm(seed=None, name=None):
    if seed is not None:
        random.seed(seed)
    
    vm_id = random.randint(0x1000, 0xFFFF)
    vm_name = name or f"NestedVM_2Tier_Arch_{vm_id:04X}"
    
    outer_key = random.randint(0x50, 0xAA)
    inner_key = random.randint(0x80, 0xEE)
    
    spec = {
        "vcpu_tier": 2,
        "vcpu_type": "nested_vm",
        "isa_name": vm_name,
        "isa_version": "2.0",
        "outer_key": outer_key,
        "inner_key": inner_key,
        "outer_opcodes": {
            "op_out_setup": 0x10,
            "op_out_dispatch": 0x30,
            "op_out_mutate_key": 0x20,
            "op_out_halt": 0xFF
        },
        "inner_opcodes": {
            "op_in_nop": 0x00,
            "op_in_load_arg": 0x01,
            "op_in_load_const": 0x02,
            "op_in_add": 0x03,
            "op_in_sub": 0x04,
            "op_in_xor": 0x05,
            "op_in_mul": 0x06,
            "op_in_ret": 0x0F
        },
        "inner_registers": 8
    }
    return spec

def export_sail_nested_vm(spec):
    name = spec["isa_name"]
    return f"""/* ==============================================================================
 * Formal Sail Specification: VCPU 2 (2-Tier Nested Hierarchical Interpreter)
 * Architecture: {name}
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
union outer_ast = {{
    OUT_SETUP      : unit,
    OUT_DISPATCH   : unit,
    OUT_MUTATE_KEY : bits(8),
    OUT_HALT       : unit
}}

/* Inner Worker VCPU Instruction AST */
union inner_ast = {{
    IN_NOP        : unit,
    IN_LOAD_ARG   : (inner_reg_idx, bits(8)),
    IN_LOAD_CONST : (inner_reg_idx, bits(32)),
    IN_ADD        : (inner_reg_idx, inner_reg_idx, inner_reg_idx),
    IN_SUB        : (inner_reg_idx, inner_reg_idx, inner_reg_idx),
    IN_XOR        : (inner_reg_idx, inner_reg_idx, inner_reg_idx),
    IN_MUL        : (inner_reg_idx, inner_reg_idx, inner_reg_idx),
    IN_RET        : (inner_reg_idx)
}}

function decode_outer(op : bits(8)) -> option(outer_ast) = {{
    match unsigned(op) {{
        0x10 => Some(OUT_SETUP()),
        0x30 => Some(OUT_DISPATCH()),
        0x20 => Some(OUT_MUTATE_KEY(0x1F)),
        0xFF => Some(OUT_HALT()),
        _    => None()
    }}
}}

function decode_inner(op : bits(8), a1 : bits(8), a2 : bits(8), a3 : bits(8)) -> option(inner_ast) = {{
    match unsigned(op) {{
        0x00 => Some(IN_NOP()),
        0x01 => Some(IN_LOAD_ARG(unsigned(a2[2..0]), a1)),
        0x02 => Some(IN_LOAD_CONST(unsigned(a2[2..0]), EXTZ(a1))),
        0x03 => Some(IN_ADD(unsigned(a1[2..0]), unsigned(a2[2..0]), unsigned(a3[2..0]))),
        0x04 => Some(IN_SUB(unsigned(a1[2..0]), unsigned(a2[2..0]), unsigned(a3[2..0]))),
        0x05 => Some(IN_XOR(unsigned(a1[2..0]), unsigned(a2[2..0]), unsigned(a3[2..0]))),
        0x06 => Some(IN_MUL(unsigned(a1[2..0]), unsigned(a2[2..0]), unsigned(a3[2..0]))),
        0x0F => Some(IN_RET(unsigned(a1[2..0]))),
        _    => None()
    }}
}}

function execute_inner(inst : inner_ast) -> bool = {{
    match inst {{
        IN_NOP()                   => true,
        IN_LOAD_ARG(dst, arg_idx)  => true,
        IN_LOAD_CONST(dst, imm)    => {{ Inner_R[dst] = imm; true }},
        IN_ADD(dst, s1, s2)        => {{ Inner_R[dst] = Inner_R[s1] + Inner_R[s2]; true }},
        IN_SUB(dst, s1, s2)        => {{ Inner_R[dst] = Inner_R[s1] - Inner_R[s2]; true }},
        IN_XOR(dst, s1, s2)        => {{ Inner_R[dst] = Inner_R[s1] ^ Inner_R[s2]; true }},
        IN_MUL(dst, s1, s2)        => {{ Inner_R[dst] = Inner_R[s1] * Inner_R[s2]; true }},
        IN_RET(src)                => {{ VM_Result = Inner_R[src]; false }}
    }}
}}
"""

# ==============================================================================
# VCPU 3: rolling_vkey (Stateful Rolling Key VM)
# ==============================================================================
def generate_rolling_vkey(seed=None, name=None):
    if seed is not None:
        random.seed(seed)
        
    vm_id = random.randint(0x1000, 0xFFFF)
    vm_name = name or f"RollingVKey_Arch_{vm_id:04X}"
    
    spec = {
        "vcpu_tier": 3,
        "vcpu_type": "rolling_vkey",
        "isa_name": vm_name,
        "isa_version": "1.0",
        "initial_vkey": 0x5A17C3D5,
        "multiplier": 33,
        "entropy_constant": 0x9E3779B9,
        "opcodes": {
            "op_add_imm": 0x01,
            "op_xor_imm": 0x02,
            "op_mul_imm": 0x03,
            "op_halt": 0xFF
        },
        "registers": 4
    }
    return spec

def export_sail_rolling_vkey(spec):
    name = spec["isa_name"]
    return f"""/* ==============================================================================
 * Formal Sail Specification: VCPU 3 (Stateful Rolling Key Virtual Machine)
 * Architecture: {name}
 * ============================================================================== */

default Order dec
$include <prelude.sail>

type r_reg_idx = range(0, 3)
register Regs : vector(4, dec, bits(32))
register VKey : bits(32)
register PC : bits(32)

union rolling_ast = {{
    R_ADD_IMM : (r_reg_idx, r_reg_idx, bits(32)),
    R_XOR_IMM : (r_reg_idx, r_reg_idx, bits(32)),
    R_MUL_IMM : (r_reg_idx, r_reg_idx, bits(32)),
    R_HALT    : (r_reg_idx)
}}

function evolve_vkey(vkey : bits(32), dec_word : bits(32)) -> bits(32) = {{
    let term : bits(32) = dec_word + 0x9E3779B9;
    (vkey * 33) ^ term
}}

function decode_rolling(op : bits(8)) -> option(rolling_ast) = {{
    match unsigned(op) {{
        0x01 => Some(R_ADD_IMM(1, 0, EXTZ(0x0A))),
        0x02 => Some(R_XOR_IMM(2, 1, EXTZ(0x2A))),
        0x03 => Some(R_MUL_IMM(3, 2, EXTZ(0x02))),
        0xFF => Some(R_HALT(3)),
        _    => None()
    }}
}}

function execute_rolling(inst : rolling_ast) -> bool = {{
    match inst {{
        R_ADD_IMM(dst, src, imm) => {{ Regs[dst] = Regs[src] + imm; true }},
        R_XOR_IMM(dst, src, imm) => {{ Regs[dst] = Regs[src] ^ imm; true }},
        R_MUL_IMM(dst, src, imm) => {{ Regs[dst] = Regs[src] * imm; true }},
        R_HALT(src)              => false
    }}
}}
"""

# ==============================================================================
# VCPU 4: ephemeral_jit (In-Memory Ephemeral Unpacking VM)
# ==============================================================================
def generate_ephemeral_vm(seed=None, name=None):
    if seed is not None:
        random.seed(seed)
        
    vm_id = random.randint(0x1000, 0xFFFF)
    vm_name = name or f"Ephemeral_JIT_Arch_{vm_id:04X}"
    
    spec = {
        "vcpu_tier": 4,
        "vcpu_type": "ephemeral_jit",
        "isa_name": vm_name,
        "isa_version": "1.0",
        "payload_size": 16,
        "xor_key": 0x5A,
        "expected_input": 25352,
        "operations": {
            "op_alloc_page": 0x01,
            "op_decrypt_payload": 0x02,
            "op_execute_verify": 0x03,
            "op_wipe_zero": 0x04
        }
    }
    return spec

def export_sail_ephemeral_vm(spec):
    name = spec["isa_name"]
    return f"""/* ==============================================================================
 * Formal Sail Specification: VCPU 4 (In-Memory Ephemeral Unpacking JIT VM)
 * Architecture: {name}
 * ============================================================================== */

default Order dec
$include <prelude.sail>

register Page_Allocated : bool
register Page_Zeroed : bool
register Decrypted_Payload : vector(16, dec, bits(8))
register Ephemeral_Result : bits(32)

union ephemeral_ast = {{
    EPH_ALLOC_MMAP : bits(32),
    EPH_DECRYPT    : bits(8),
    EPH_EXECUTE    : bits(32),
    EPH_FREE_ZERO  : unit
}}

function execute_ephemeral(inst : ephemeral_ast) -> unit = {{
    match inst {{
        EPH_ALLOC_MMAP(sz) => {{ Page_Allocated = true }},
        EPH_DECRYPT(k)     => {{ Page_Zeroed = false }},
        EPH_EXECUTE(input) => {{ Ephemeral_Result = if input == 25352 then EXTZ(0x01) else EXTZ(0x00) }},
        EPH_FREE_ZERO()    => {{ Page_Zeroed = true; Page_Allocated = false }}
    }}
}}
"""

# ==============================================================================
# CLI Entrypoint
# ==============================================================================
def main():
    parser = argparse.ArgumentParser(description="OcaSorry Formal 4-VCPU Sail & JSON Architecture Synthesizer")
    parser.add_argument("-o", "--output-json", default="visa_spec.json", help="Path to output JSON ISA specification")
    parser.add_argument("-s", "--output-sail", default=None, help="Path to output formal Sail specification (.sail)")
    parser.add_argument("--vcpu", choices=["visa", "nested_vm", "rolling_vkey", "ephemeral", "all"], default="all",
                        help="Target VCPU tier to synthesize (default: all 4 VCPUs)")
    parser.add_argument("--output-dir", default=None, help="Output directory to write all 4 Sail and JSON specs")
    parser.add_argument("--seed", type=int, default=None, help="Deterministic random seed")
    parser.add_argument("--name", default=None, help="Custom ISA architecture name")
    
    args = parser.parse_args()
    
    out_dir = args.output_dir or os.path.dirname(args.output_json) or "."
    os.makedirs(out_dir, exist_ok=True)
    
    if args.vcpu == "all" or args.output_dir is not None:
        # Generate all 4 VCPU Sail specifications and JSON schemas
        vcpus = [
            ("vcpu1_visa", generate_random_visa(args.seed, args.name or "vISA_Vector_Cascade_Arch"), export_sail_visa),
            ("vcpu2_nested_vm", generate_nested_vm(args.seed, "NestedVM_Hierarchical_Arch"), export_sail_nested_vm),
            ("vcpu3_rolling_vkey", generate_rolling_vkey(args.seed, "RollingVKey_Stateful_Arch"), export_sail_rolling_vkey),
            ("vcpu4_ephemeral_jit", generate_ephemeral_vm(args.seed, "Ephemeral_JIT_Security_Arch"), export_sail_ephemeral_vm),
        ]
        
        for prefix, spec, export_fn in vcpus:
            j_path = os.path.join(out_dir, f"{prefix}.json")
            s_path = os.path.join(out_dir, f"{prefix}.sail")
            
            with open(j_path, "w") as f:
                json.dump(spec, f, indent=2)
            with open(s_path, "w") as f:
                f.write(export_fn(spec))
            print(f"[+] [VCPU {spec.get('vcpu_tier', 1)}] Synthesized {spec['isa_name']} -> {j_path} & {s_path}")
            
        # Also symlink/write main default visa_spec.json for legacy CLI if requested
        if args.output_json and args.output_json != "visa_spec.json":
            v1_spec = vcpus[0][1]
            with open(args.output_json, "w") as f:
                json.dump(v1_spec, f, indent=2)
            sail_p = args.output_sail or args.output_json.replace(".json", ".sail")
            with open(sail_p, "w") as f:
                f.write(export_sail_visa(v1_spec))
    else:
        generators = {
            "visa": (generate_random_visa, export_sail_visa),
            "nested_vm": (generate_nested_vm, export_sail_nested_vm),
            "rolling_vkey": (generate_rolling_vkey, export_sail_rolling_vkey),
            "ephemeral": (generate_ephemeral_vm, export_sail_ephemeral_vm),
        }
        gen_fn, export_fn = generators[args.vcpu]
        spec = gen_fn(seed=args.seed, name=args.name)
        
        with open(args.output_json, "w") as f:
            json.dump(spec, f, indent=2)
        print(f"[+] Synthesized JSON Spec -> {args.output_json} ({spec['isa_name']})")
        
        sail_path = args.output_sail or args.output_json.replace(".json", ".sail")
        if not sail_path.endswith(".sail"):
            sail_path += ".sail"
        with open(sail_path, "w") as f:
            f.write(export_fn(spec))
        print(f"[+] Formal Sail Architecture Spec -> {sail_path}")

if __name__ == "__main__":
    main()
