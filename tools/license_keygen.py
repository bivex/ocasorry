#!/usr/bin/env python3
"""
tools/license_keygen.py - 4-VCPU Federated License Key Generator & Validator
Generates valid 16-character license keys satisfying the 4-Tier OcaSorry Virtualization Cascade:

Cascade Equations:
  - VCPU 1 (random_vISA Vector VM) : h1 = vcpu1_vector_parity(key) == 12687
  - VCPU 2 (Nested Multi-Layer VM) : h2 = h1 + 21 == 12708
  - VCPU 3 (Rolling Key VM)        : h3 = ((h2 + 10) ^ 42) * 2 == 25352
  - VCPU 4 (Ephemeral JIT VM)      : is_valid = (h3 == 25352) -> 1 (UNLOCKED)
"""

import sys
import os
import argparse
import random
import string
import json
import time

TARGET_H1 = 12687
TARGET_H2 = 12708
TARGET_H3 = 25352

ALPHABET = string.ascii_uppercase + string.digits

def vcpu1_compute(key: str) -> int:
    """Simulates VCPU 1 (random_vISA Vector Processor)."""
    acc = 0x1337
    parity = 0x5A
    raw = key.encode("ascii", errors="replace")
    for i, ch in enumerate(raw):
        acc = (acc + (ch * (i + 1))) ^ parity
        parity = (parity + ch) & 0xFF
    return acc

def vcpu2_compute(h1: int) -> int:
    """Simulates VCPU 2 (2-Tier Nested Multi-Layer VM)."""
    return h1 + 21

def vcpu3_compute(h2: int) -> int:
    """Simulates VCPU 3 (Stateful Rolling Key VM)."""
    return ((h2 + 10) ^ 42) * 2

def vcpu4_compute(h3: int) -> int:
    """Simulates VCPU 4 (In-Memory Ephemeral JIT VM)."""
    return 1 if h3 == TARGET_H3 else 0

def trace_key(key: str) -> dict:
    """Evaluates a license key through the entire 4-VCPU pipeline."""
    if len(key) != 16:
        return {
            "key": key,
            "length": len(key),
            "is_valid": False,
            "error": f"Invalid key length: {len(key)} (expected 16 chars)"
        }
    
    h1 = vcpu1_compute(key)
    h2 = vcpu2_compute(h1)
    h3 = vcpu3_compute(h2)
    valid = (vcpu4_compute(h3) == 1)
    
    return {
        "key": key,
        "length": len(key),
        "vcpu1_h1": h1,
        "vcpu1_target": TARGET_H1,
        "vcpu2_h2": h2,
        "vcpu2_target": TARGET_H2,
        "vcpu3_h3": h3,
        "vcpu3_target": TARGET_H3,
        "is_valid": valid,
        "status": "UNLOCKED (Valid Key)" if valid else "REJECTED (Invalid Key)"
    }

def solve_key(prefix: str = "PRO-", max_attempts: int = 200000) -> str:
    """
    Fast Meet-in-the-Middle solver to find valid 16-character keys with given prefix.
    Format: <PREFIX><PART1>-<PART2>-<PART3> -> Exactly 16 chars.
    """
    clean_prefix = prefix.upper()
    if not clean_prefix.endswith("-") and len(clean_prefix) <= 4:
        clean_prefix += "-"
        
    remaining_len = 16 - len(clean_prefix)
    if remaining_len < 4:
        clean_prefix = "PRO-"
        remaining_len = 12

    # Fast 2-character exhaustive suffix search
    body_len = remaining_len - 2
    
    for _ in range(max_attempts):
        # Generate random body: e.g. "9842-KLM9-"
        rand_body = "".join(random.choices(ALPHABET, k=body_len))
        
        # Inject standard dashed formatting if appropriate
        candidate_base = clean_prefix + rand_body
        
        # Partially compute VCPU state for first 14 chars
        acc = 0x1337
        parity = 0x5A
        for i, ch in enumerate(candidate_base.encode("ascii")):
            acc = (acc + (ch * (i + 1))) ^ parity
            parity = (parity + ch) & 0xFF
            
        # Search last 2 characters (36 * 36 = 1296 combinations)
        for c1 in ALPHABET:
            ch1 = ord(c1)
            acc1 = (acc + (ch1 * 15)) ^ parity
            parity1 = (parity + ch1) & 0xFF
            
            for c2 in ALPHABET:
                ch2 = ord(c2)
                acc2 = (acc1 + (ch2 * 16)) ^ parity1
                if acc2 == TARGET_H1:
                    return candidate_base + c1 + c2

    # Fallback to random search if exhaustive suffix fails
    return None

def generate_keys(count: int = 1, prefix: str = "PRO-") -> list:
    keys = []
    seen = set()
    for _ in range(count):
        k = solve_key(prefix)
        if k and k not in seen:
            seen.add(k)
            keys.append(k)
    return keys

def main():
    parser = argparse.ArgumentParser(
        description="OcaSorry 4-VCPU Federated License Key Generator & Validator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate 5 PRO license keys:
  python3 tools/license_keygen.py -n 5 --prefix PRO-

  # Generate Enterprise keys and verify:
  python3 tools/license_keygen.py -n 3 --prefix ENT- --verify

  # Verify an existing key:
  python3 tools/license_keygen.py --check "PRO-9842-KLM9-77"
        """
    )
    parser.add_argument("-n", "--count", type=int, default=1, help="Number of valid license keys to generate (default: 1)")
    parser.add_argument("-p", "--prefix", default="PRO-", help="Key tier prefix (e.g. PRO-, ENT-, DEV-, ULT-)")
    parser.add_argument("-c", "--check", metavar="KEY", help="Validate and trace an existing license key")
    parser.add_argument("-j", "--json", action="store_true", help="Output results in JSON format")
    parser.add_argument("-o", "--output", help="Save generated keys to a file")
    parser.add_argument("-v", "--verify", action="store_true", help="Print detailed 4-VCPU trace for each generated key")

    args = parser.parse_args()

    # Mode 1: Validate specific key
    if args.check:
        info = trace_key(args.check)
        if args.json:
            print(json.dumps(info, indent=2))
        else:
            print("=" * 65)
            print(f"       OcaSorry 4-VCPU Key Verification: {args.check}")
            print("=" * 65)
            print(f"  Length        : {info['length']} / 16 chars")
            print(f"  VCPU 1 (h1)   : {info.get('vcpu1_h1')} (Target: {TARGET_H1})")
            print(f"  VCPU 2 (h2)   : {info.get('vcpu2_h2')} (Target: {TARGET_H2})")
            print(f"  VCPU 3 (h3)   : {info.get('vcpu3_h3')} (Target: {TARGET_H3})")
            print(f"  VCPU 4 Result : {info['status']}")
            print("=" * 65)
        sys.exit(0 if info.get("is_valid") else 1)

    # Mode 2: Generate valid keys
    t0 = time.time()
    keys = generate_keys(count=args.count, prefix=args.prefix)
    elapsed = (time.time() - t0) * 1000.0

    if not keys:
        print("[-] Error: Failed to generate license keys satisfying cascade equations.", file=sys.stderr)
        sys.exit(1)

    if args.json:
        result_data = {
            "generated_count": len(keys),
            "generation_time_ms": round(elapsed, 2),
            "keys": [trace_key(k) if args.verify else k for k in keys]
        }
        output_text = json.dumps(result_data, indent=2)
        print(output_text)
    else:
        print("=" * 65)
        print(f"   OcaSorry 4-VCPU License Keygen ({len(keys)} keys generated in {elapsed:.1f}ms)")
        print("=" * 65)
        for i, k in enumerate(keys, 1):
            if args.verify:
                tr = trace_key(k)
                print(f"  [{i:02d}] {k}  -> [h1={tr['vcpu1_h1']}, h2={tr['vcpu2_h2']}, h3={tr['vcpu3_h3']} | VALID]")
            else:
                print(f"  [{i:02d}] {k}")
        print("=" * 65)

    if args.output:
        with open(args.output, "w") as f:
            for k in keys:
                f.write(k + "\n")
        print(f"[+] Saved {len(keys)} keys to: {args.output}")

if __name__ == "__main__":
    main()
