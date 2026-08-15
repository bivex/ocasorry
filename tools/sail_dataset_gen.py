#!/usr/bin/env python3
"""
sail_dataset_gen.py — OcaSorry Sail ISA Dataset Generator
Generates N Sail ISA specs via ocasorry_synth, extracts feature vectors,
scores them for uniqueness / entropy / cryptographic strength, and writes
a JSON dataset ready for mlx_sail_optimizer.py training.
"""

import argparse
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

SYNTH_BIN = Path(__file__).parent.parent / "_build/default/bin/vectis_synth.exe"
GF_POLYS   = [0x1B, 0x1D, 0x4D, 0x8D, 0xA3, 0xC5]

# ─── Feature extraction ───────────────────────────────────────────────────────

def entropy(values):
    if not values:
        return 0.0
    total = len(values)
    counts = Counter(values)
    return -sum((c / total) * math.log2(c / total) for c in counts.values())

def hamming_weight(n):
    return bin(n).count("1")

def gf_poly_strength(poly):
    primitive = {0x1B: 1.0, 0x4D: 0.95, 0x8D: 0.9, 0xA3: 0.85, 0x1D: 0.8, 0xC5: 0.88}
    return primitive.get(poly, 0.5)

def mnemonic_entropy(text):
    tokens = re.findall(r'[A-Z]{2,}', text)
    if not tokens:
        return 0.0
    return entropy([hash(t) & 0xFF for t in tokens])

def parse_visa_sail(text):
    feats = {}
    m = re.search(r'GF_poly=0x([0-9A-Fa-f]+)', text)
    feats['gf_poly'] = int(m.group(1), 16) if m else 0x1B
    m = re.search(r'ROL=(\d+)', text)
    feats['rol_const'] = int(m.group(1)) if m else 7
    m = re.search(r'imm(\d+)', text)
    feats['imm_bits'] = int(m.group(1)) if m else 14
    opcodes = [int(x) for x in re.findall(r'^\s+(\d+) => Some\(', text, re.MULTILINE)]
    feats['opcode_count']   = len(opcodes)
    feats['opcode_entropy'] = entropy(opcodes) if opcodes else 0.0
    feats['mnemonic_entropy'] = mnemonic_entropy(text)
    feats['syllable_count'] = len(set(re.findall(r'[A-Z]{2}', text)))
    feats['type_count']     = len(re.findall(r'^type\s', text, re.MULTILINE))
    feats['register_count'] = len(re.findall(r'^register\s', text, re.MULTILINE))
    return feats

def parse_nested_sail(text):
    feats = {}
    for key, default in [('hash_bits', 32), ('stack_depth', 8), ('state_regs', 4)]:
        m = re.search(rf'{key}=(\d+)', text)
        feats[key] = int(m.group(1)) if m else default
    feats['outer_ops']        = len(re.findall(r'OX_[A-Z]+', text))
    feats['inner_ops']        = len(re.findall(r'IX_[A-Z]+', text))
    feats['mnemonic_entropy'] = mnemonic_entropy(text)
    feats['type_count']       = len(re.findall(r'^type\s', text, re.MULTILINE))
    feats['register_count']   = len(re.findall(r'^register\s', text, re.MULTILINE))
    return feats

def parse_rolling_sail(text):
    feats = {}
    for key, default in [('key_bits', 32), ('state_regs', 4)]:
        m = re.search(rf'{key}=(\d+)', text)
        feats[key] = int(m.group(1)) if m else default
    m = re.search(r'GF_poly=0x([0-9A-Fa-f]+)', text)
    feats['gf_poly'] = int(m.group(1), 16) if m else 0x1B
    m = re.search(r'LCG: mult=(\d+)', text)
    feats['lcg_mult'] = int(m.group(1)) if m else 33
    m = re.search(r'delta=0x([0-9A-Fa-f]+)', text)
    feats['lcg_delta'] = int(m.group(1), 16) if m else 0x9E3779B9
    feats['mnemonic_entropy'] = mnemonic_entropy(text)
    feats['rk_ops']         = len(re.findall(r'RK_[A-Z]+', text))
    feats['type_count']     = len(re.findall(r'^type\s', text, re.MULTILINE))
    feats['register_count'] = len(re.findall(r'^register\s', text, re.MULTILINE))
    return feats

def parse_ephemeral_sail(text):
    feats = {}
    m = re.search(r'page=2\^(\d+)', text)
    feats['page_shift'] = int(m.group(1)) if m else 12
    m = re.search(r'wipe_passes=(\d+)', text)
    feats['wipe_passes'] = int(m.group(1)) if m else 3
    m = re.search(r'jit_regs=(\d+)', text)
    feats['jit_regs'] = int(m.group(1)) if m else 4
    m = re.search(r'guard=0x([0-9A-Fa-f]+)', text)
    feats['guard_magic'] = int(m.group(1), 16) if m else 0xDEAD0000
    feats['mnemonic_entropy'] = mnemonic_entropy(text)
    feats['ep_ops']         = len(re.findall(r'EP_[A-Z]+', text))
    feats['jit_states']     = len(re.findall(r'JIT_\w+_[A-Z]+', text))
    feats['type_count']     = len(re.findall(r'^type\s', text, re.MULTILINE))
    feats['register_count'] = len(re.findall(r'^register\s', text, re.MULTILINE))
    return feats

# ─── Quality scoring ──────────────────────────────────────────────────────────

def score_visa(f):
    s  = min(f['opcode_entropy'] / 4.0, 1.0) * 0.30
    s += min(f['mnemonic_entropy'] / 6.0, 1.0) * 0.20
    s += min(f['syllable_count'] / 32.0, 1.0) * 0.10
    s += gf_poly_strength(f['gf_poly']) * 0.20
    s += min(f['rol_const'] / 15.0, 1.0) * 0.10
    s += (f['imm_bits'] - 12) / 4.0 * 0.10
    return min(max(s, 0.0), 1.0)

def score_nested(f):
    s  = min(f['hash_bits'] / 64.0, 1.0) * 0.25
    s += min(f['stack_depth'] / 16.0, 1.0) * 0.20
    s += min(f['state_regs'] / 12.0, 1.0) * 0.15
    s += min(f['mnemonic_entropy'] / 6.0, 1.0) * 0.20
    s += min((f['outer_ops'] + f['inner_ops']) / 20.0, 1.0) * 0.20
    return min(max(s, 0.0), 1.0)

def score_rolling(f):
    s  = min(f['key_bits'] / 64.0, 1.0) * 0.25
    s += min(f['state_regs'] / 8.0, 1.0) * 0.20
    s += gf_poly_strength(f['gf_poly']) * 0.25
    s += min(f['mnemonic_entropy'] / 6.0, 1.0) * 0.20
    lcg_q = min(bin(f.get('lcg_delta', 0)).count('1') / 32.0, 1.0)
    s += lcg_q * 0.10
    return min(max(s, 0.0), 1.0)

def score_ephemeral(f):
    s  = (f['page_shift'] - 12) / 3.0 * 0.20
    s += min(f['wipe_passes'] / 6.0, 1.0) * 0.15
    s += min(f['jit_regs'] / 7.0, 1.0) * 0.15
    s += min(f['mnemonic_entropy'] / 6.0, 1.0) * 0.20
    s += min(f['jit_states'] / 12.0, 1.0) * 0.15
    s += hamming_weight(f.get('guard_magic', 0)) / 32.0 * 0.15
    return min(max(s, 0.0), 1.0)

PARSERS = {
    'visa':      (parse_visa_sail,      score_visa),
    'nested':    (parse_nested_sail,    score_nested),
    'rolling':   (parse_rolling_sail,   score_rolling),
    'ephemeral': (parse_ephemeral_sail, score_ephemeral),
}
SAIL_FILES = {
    'visa':      'vcpu1_visa.sail',
    'nested':    'vcpu2_nested_vm.sail',
    'rolling':   'vcpu3_rolling_vkey.sail',
    'ephemeral': 'vcpu4_ephemeral_jit.sail',
}

# ─── Feature vector (dim=9 fixed) ────────────────────────────────────────────

def to_fvec(vcpu, f):
    if vcpu == 'visa':
        return [
            f.get('gf_poly', 0x1B) / 255.0,
            f.get('rol_const', 7) / 15.0,
            (f.get('imm_bits', 14) - 12) / 4.0,
            min(f.get('opcode_entropy', 0) / 4.0, 1.0),
            min(f.get('mnemonic_entropy', 0) / 6.0, 1.0),
            min(f.get('syllable_count', 0) / 32.0, 1.0),
            f.get('opcode_count', 0) / 16.0,
            min(f.get('type_count', 0) / 5.0, 1.0),
            min(f.get('register_count', 0) / 6.0, 1.0),
        ]
    if vcpu == 'nested':
        return [
            f.get('hash_bits', 32) / 64.0,
            f.get('stack_depth', 8) / 16.0,
            f.get('state_regs', 4) / 12.0,
            min(f.get('mnemonic_entropy', 0) / 6.0, 1.0),
            min(f.get('outer_ops', 0) / 8.0, 1.0),
            min(f.get('inner_ops', 0) / 14.0, 1.0),
            min(f.get('type_count', 0) / 5.0, 1.0),
            min(f.get('register_count', 0) / 8.0, 1.0),
            0.0,
        ]
    if vcpu == 'rolling':
        return [
            f.get('key_bits', 32) / 64.0,
            f.get('state_regs', 4) / 8.0,
            f.get('gf_poly', 0x1B) / 255.0,
            f.get('lcg_mult', 33) / 65.0,
            min(f.get('lcg_delta', 0) / 0xFFFFFFFF, 1.0),
            min(f.get('mnemonic_entropy', 0) / 6.0, 1.0),
            min(f.get('rk_ops', 0) / 12.0, 1.0),
            min(f.get('type_count', 0) / 4.0, 1.0),
            min(f.get('register_count', 0) / 6.0, 1.0),
        ]
    if vcpu == 'ephemeral':
        return [
            (f.get('page_shift', 12) - 12) / 3.0,
            f.get('wipe_passes', 3) / 6.0,
            f.get('jit_regs', 4) / 7.0,
            min(f.get('guard_magic', 0) / 0xFFFFFFFF, 1.0),
            min(f.get('mnemonic_entropy', 0) / 6.0, 1.0),
            min(f.get('ep_ops', 0) / 12.0, 1.0),
            min(f.get('jit_states', 0) / 12.0, 1.0),
            min(f.get('type_count', 0) / 4.0, 1.0),
            min(f.get('register_count', 0) / 8.0, 1.0),
        ]
    return [0.0] * 9

# ─── Generation ───────────────────────────────────────────────────────────────

def generate_sample(seed, tmpdir):
    out_dir = os.path.join(tmpdir, f"s{seed}")
    os.makedirs(out_dir, exist_ok=True)
    try:
        r = subprocess.run(
            [str(SYNTH_BIN), "--vcpu", "all",
             "--output-dir", out_dir,
             "--seed", str(seed),
             "--name", f"ISA{seed:06d}"],
            capture_output=True, text=True, timeout=15
        )
        if r.returncode != 0:
            return None
    except Exception:
        return None

    sample = {"seed": seed, "vcpus": {}}
    for vcpu, fname in SAIL_FILES.items():
        path = os.path.join(out_dir, fname)
        if not os.path.exists(path):
            continue
        text = open(path).read()
        parse_fn, score_fn = PARSERS[vcpu]
        feats = parse_fn(text)
        score = score_fn(feats)
        fvec  = to_fvec(vcpu, feats)
        sample["vcpus"][vcpu] = {
            "features":       feats,
            "feature_vector": fvec,
            "quality_score":  round(score, 6),
        }
    return sample if sample["vcpus"] else None

# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description="OcaSorry Sail ISA Dataset Generator")
    ap.add_argument("-n", "--count",      type=int, default=2000)
    ap.add_argument("-o", "--output",     default="tools/sail_dataset.json")
    ap.add_argument("--seed-start",       type=int, default=1)
    ap.add_argument("--workers",          type=int, default=8)
    args = ap.parse_args()

    if not SYNTH_BIN.exists():
        print(f"[!] Build first: eval $(opam env) && dune build")
        sys.exit(1)

    print(f"[*] Generating {args.count} Sail ISA samples "
          f"(seeds {args.seed_start}..{args.seed_start+args.count-1})")
    print(f"[*] Synth binary: {SYNTH_BIN}")
    print(f"[*] Workers: {args.workers}")

    dataset = []
    tmpdir  = tempfile.mkdtemp(prefix="ocasorry_sail_")
    ok = err = 0

    try:
        seeds = list(range(args.seed_start, args.seed_start + args.count))
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            futures = {pool.submit(generate_sample, s, tmpdir): s for s in seeds}
            for i, fut in enumerate(as_completed(futures)):
                sample = fut.result()
                if sample:
                    dataset.append(sample)
                    ok += 1
                else:
                    err += 1
                if (i + 1) % 200 == 0 or i + 1 == args.count:
                    print(f"  [{i+1:4d}/{args.count}]  ok={ok}  err={err}  "
                          f"avg_score={sum(s['vcpus'].get('visa',{}).get('quality_score',0) for s in dataset)/max(ok,1):.3f}")
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)

    print(f"\n[+] Collected {len(dataset)} samples")
    print(f"[+] Dataset statistics per VCPU:")
    for vcpu in SAIL_FILES:
        scores = [s["vcpus"][vcpu]["quality_score"]
                  for s in dataset if vcpu in s["vcpus"]]
        if scores:
            avg = sum(scores) / len(scores)
            mx, mn = max(scores), min(scores)
            top10 = sorted(scores, reverse=True)[:10]
            print(f"    {vcpu:10s}  n={len(scores):4d}  min={mn:.3f}  avg={avg:.3f}"
                  f"  max={mx:.3f}  top10_avg={sum(top10)/len(top10):.3f}")

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w") as f:
        json.dump({
            "meta": {
                "count":       len(dataset),
                "seed_start":  args.seed_start,
                "vcpus":       list(SAIL_FILES.keys()),
                "feature_dim": 9,
                "score_dims":  {"visa": "entropy+gf+rol+imm", "nested": "hash+stack+ops",
                                "rolling": "key+gf+lcg+state", "ephemeral": "page+wipe+jit+guard"},
            },
            "samples": dataset,
        }, f, indent=2)

    size_kb = out_path.stat().st_size // 1024
    print(f"[+] Dataset saved -> {out_path}  ({size_kb} KB)")

if __name__ == "__main__":
    main()
