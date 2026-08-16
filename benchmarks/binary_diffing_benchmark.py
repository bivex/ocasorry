#!/usr/bin/env python3
"""
benchmarks/binary_diffing_benchmark.py — Vectis Binary Diffing & CFG Alignment Benchmark

Threat Model:
An automated binary diffing tool (e.g. BinDiff, Diaphora, Ghidra Version Tracking) attempts to
match functions across builds by comparing Control Flow Graph (CFG) topology, basic block instruction
n-grams, and cyclomatic complexity.

Evaluates:
1. Baseline Unobfuscated: Build 1 vs Build 2 of plain C code
2. Vectis Obfuscated: 3 independent randomized builds per iteration,
   N = ITERATIONS statistical repeats (Median, Min, Max, P95, StdDev).
   The obfuscator draws fresh OS entropy per build (unique ISA layout each
   invocation), so single-shot similarity varies widely; only the median
   over N repeats is a stable regression signal.

Metrics:
- Instruction 3-Gram Jaccard Similarity (all pairwise build combinations)
- Basic Block Count Expansion Factor
- Automated Function Matching Resistance (0..100)
"""

import os
import sys
import json
import time
import subprocess
import tempfile
import numpy as np

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN_BIN     = os.path.join(PROJECT_ROOT, "_build/default/bin/main.exe")

ITERATIONS   = 20     # Number of statistical repeats (3 randomized builds each)
BUILDS_PER_ITERATION = 3

SAMPLE_C_CODE = """\
extern int printf(const char *format, ...);

int compute_key(int a, int b) {
    int s = 0;
    for (int i = 0; i < 4; ++i) {
        if ((a + i) % 2 == 0) {
            s += (b ^ (i * 17));
        } else {
            s -= (a ^ (i * 31));
        }
    }
    return s;
}

int main(int argc, char **argv) {
    printf("%d\\n", compute_key(10, 20));
    return 0;
}
"""

def extract_disassembly_blocks(bin_path):
    """Disassembles binary using otool/objdump to extract basic blocks & instructions."""
    cmd = ["objdump", "-d", bin_path] if sys.platform != "darwin" else ["otool", "-tv", bin_path]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
        lines = res.stdout.splitlines()
    except Exception:
        return []
    
    instructions = []
    for line in lines:
        parts = line.strip().split()
        if len(parts) >= 2 and not line.endswith(":"):
            # Normalize mnemonic
            mnemonic = parts[0] if sys.platform != "darwin" else (parts[1] if len(parts) > 1 else "")
            if mnemonic and not mnemonic.endswith(":"):
                instructions.append(mnemonic.lower())
    return instructions

def compute_ngrams(seq, n=3):
    if len(seq) < n:
        return set(seq)
    return set(tuple(seq[i:i+n]) for i in range(len(seq) - n + 1))

def jaccard_similarity(set_a, set_b):
    if not set_a and not set_b:
        return 1.0
    if not set_a or not set_b:
        return 0.0
    intersection = len(set_a.intersection(set_b))
    union = len(set_a.union(set_b))
    return float(intersection) / max(1, union)

def build_obfuscated(src_c, tmpdir, tag):
    """One randomized Vectis build: fresh OS entropy -> unique ISA layout."""
    obf_c   = os.path.join(tmpdir, f"obf_{tag}.c")
    obf_bin = os.path.join(tmpdir, f"obf_{tag}.bin")
    subprocess.run([
        MAIN_BIN, "-i", src_c, "-o", obf_c,
        "--virtualize", "--poly-mba", "--opaque", "--dyn-opaque",
        "--rolling-vkey", "--vcpu-scramble",
        "--decentralized-disp", "--split-bb", "--bcf", "--relational-morph",
        "--indirect", "--micro-dispatcher"
    ], check=True, capture_output=True)
    subprocess.run(["clang", "-w", "-O2", obf_c, "-o", obf_bin], check=True)
    return extract_disassembly_blocks(obf_bin)


def stats(values):
    arr = np.asarray(values, dtype=float)
    return {
        "median": float(np.median(arr)),
        "mean":   float(np.mean(arr)),
        "std":    float(np.std(arr)),
        "min":    float(np.min(arr)),
        "max":    float(np.max(arr)),
        "p95":    float(np.percentile(arr, 95)),
    }


def run_benchmark():
    iterations = ITERATIONS
    for i, arg in enumerate(sys.argv[1:], 1):
        if arg == "--iterations" and i + 1 < len(sys.argv):
            iterations = max(1, int(sys.argv[i + 1]))

    print("\n" + "=" * 78)
    print(f"      VECTIS BINARY DIFFING & CFG ALIGNMENT RESISTANCE BENCHMARK "
          f"(STATISTICAL N={iterations})")
    print("=" * 78)
    print("Threat Model: Automated Binary Diffing (BinDiff / Diaphora) graph matching.\n")

    tmpdir = tempfile.mkdtemp(prefix="vectis_diff_")
    src_c = os.path.join(tmpdir, "orig.c")
    with open(src_c, "w") as f:
        f.write(SAMPLE_C_CODE)

    # 1. Baseline: Compile 2 builds of unobfuscated C code (deterministic)
    base_bin1 = os.path.join(tmpdir, "base1.bin")
    base_bin2 = os.path.join(tmpdir, "base2.bin")
    subprocess.run(["clang", "-w", "-O2", src_c, "-o", base_bin1], check=True)
    subprocess.run(["clang", "-w", "-O2", src_c, "-o", base_bin2], check=True)

    insns_base1 = extract_disassembly_blocks(base_bin1)
    insns_base2 = extract_disassembly_blocks(base_bin2)
    jaccard_baseline = jaccard_similarity(
        compute_ngrams(insns_base1, n=3), compute_ngrams(insns_base2, n=3))

    # 2. N statistical iterations x 3 independent randomized builds each.
    #    Similarity is collected over ALL pairwise combinations; expansion
    #    is collected per iteration (first build vs baseline).
    pair_sims = []
    expansions = []
    insn_counts_obf = []

    t_start = time.perf_counter()
    for r in range(iterations):
        insns_obf = [build_obfuscated(src_c, tmpdir, f"{r}_{i}")
                     for i in range(BUILDS_PER_ITERATION)]
        insn_counts_obf.append(len(insns_obf[0]))
        expansions.append(len(insns_obf[0]) / max(1, len(insns_base1)))
        for i in range(len(insns_obf)):
            for j in range(i + 1, len(insns_obf)):
                sim = jaccard_similarity(
                    compute_ngrams(insns_obf[i], n=3),
                    compute_ngrams(insns_obf[j], n=3))
                pair_sims.append(sim)
        print(f"[*] Iteration {r + 1}/{iterations} "
              f"(last 3-gram sim: {pair_sims[-1] * 100.0:.1f}%)", flush=True)

    elapsed = time.perf_counter() - t_start

    sim_stats   = stats(pair_sims)
    exp_stats   = stats(expansions)
    med_sim     = sim_stats["median"]
    # Diffing resistance score: how much lower is similarity compared to baseline
    diffing_resistance = max(0.0, (1.0 - med_sim) * 100.0)

    results = {
        "iterations": iterations,
        "builds_per_iteration": BUILDS_PER_ITERATION,
        "pairwise_samples": len(pair_sims),
        "baseline_unobfuscated_similarity": round(jaccard_baseline, 4),
        "vectis_obfuscated_similarity": round(med_sim, 4),
        "similarity_stats": {k: round(v, 4) for k, v in sim_stats.items()},
        "code_expansion_factor": round(exp_stats["median"], 2),
        "expansion_stats": {k: round(v, 2) for k, v in exp_stats.items()},
        "diffing_resistance_score": round(diffing_resistance, 2),
        "instruction_count_baseline": len(insns_base1),
        "instruction_count_obfuscated_median": int(np.median(insn_counts_obf)),
        "elapsed_sec": round(elapsed, 1),
    }

    print("-" * 78)
    print(f"[*] Baseline Unobfuscated Builds Similarity:   {jaccard_baseline * 100.0:5.1f}%  (Trivially matchable by BinDiff)")
    print(f"[*] Vectis Randomized Builds Similarity (Med): {med_sim * 100.0:5.1f}%"
          f"  (±{sim_stats['std'] * 100.0:.1f}σ | min {sim_stats['min'] * 100.0:.1f}%"
          f" | max {sim_stats['max'] * 100.0:.1f}% | {len(pair_sims)} pairs)")
    print(f"[*] Code Instruction Expansion (Med):          {exp_stats['median']:5.1f}x"
          f"  (±{exp_stats['std']:.1f}σ | min {exp_stats['min']:.1f}x | max {exp_stats['max']:.1f}x)")
    print(f"[*] Binary Diffing Inversion Resistance:       {diffing_resistance:5.1f} / 100.0"
          f"  (from median similarity)")
    print("-" * 78)
    print(f"  Summary: Automated graph matching confidence reduced by "
          f"{((jaccard_baseline - med_sim) / max(0.001, jaccard_baseline)) * 100.0:.1f}%"
          f" (median over N={iterations} iterations x {BUILDS_PER_ITERATION} builds, "
          f"{elapsed:.0f}s total).")
    print("=" * 78 + "\n")

    out_json = os.path.join(PROJECT_ROOT, "benchmarks/binary_diffing_results.json")
    with open(out_json, "w") as f:
        json.dump(results, f, indent=2)
    print(f"[✓] Statistical binary diffing benchmark results saved to {out_json}\n")

if __name__ == "__main__":
    run_benchmark()
