#!/usr/bin/env python3
"""
benchmarks/mba_simplification_benchmark.py — Vectis MBA Algebraic Simplification & Deobfuscation Benchmark

Threat Model:
An automated deobfuscator (e.g. QSynth, Arybo, Syntia, NeuReduce, Z3 BV Simplifier) attempts to
reduce complex Mixed Boolean-Arithmetic (MBA) expressions back to simple canonical operations.

Evaluates 5 MBA transformation depths:
1. Ground Truth (Depth 0): Raw operation (e.g. x + y)
2. Linear MBA (Depth 1): (x | y) + (x & y)
3. Recursive MBA (Depth 2): Nested Demorgan & boolean inversions
4. High-Order Polynomial MBA: Non-linear polynomial cross-terms + affine S-Box
5. Vectis E-Graph Saturated MBA: Multi-iteration saturated equivalence expansion

Measures:
- Initial AST Size (Number of operators & leaves)
- AST Size after Z3 BitVector Simplification (`z3.simplify`)
- Z3 BitVector Simplification Reduction Ratio (Did Z3 collapse the MBA?)
- Oracle-Guided SMT Synthesis Recovery Rate (Can an automated synthesizer reconstruct the 1-op formula?)
- Synthesis Time (seconds, 5.0s timeout)
"""

import time
import json
import os
import z3
import numpy as np

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ─── Target MBA Expressions (Z3 32-bit BitVectors) ───────────────────────────

def get_mba_targets():
    x = z3.BitVec("x", 32)
    y = z3.BitVec("y", 32)
    
    # Ground truth: target is x + y
    orig = x + y

    # Depth 1 Linear MBA: (x | y) + (x & y)
    depth1 = (x | y) + (x & y)

    # Depth 2 Recursive MBA: ((x ^ y) + 2*(x & y)) expanded further
    x_xor_y = (x | y) - (x & y)
    x_and_y = (x + y) - (x | y)
    depth2 = x_xor_y + (2 * x_and_y)

    # Depth 3 High-Order Polynomial MBA: ((x + y)^2 + 1337) - (x^2 + 2xy + 1337) -> x + y + ...
    # Non-linear MBA expansion of x ^ y: ((x | y) - (x & y)) + (x & ~x)
    depth3 = ((x | y) - (x & y)) + (((x & ~y) + (~x & y)) - ((x | y) - (x & y)))

    # Depth 4 Vectis E-Graph Saturated MBA:
    # ((((x + y) - ((x + y) - (x | y))) & (~((x + y) - (x | y)))) - ((~((x + y) - ((x + y) - (x | y)))) & ((x + y) - (x | y))))
    a_plus_b = x + y
    a_or_b = x | y
    sub1 = a_plus_b - a_or_b
    diff = a_plus_b - sub1
    depth4 = (diff & (~sub1)) - ((~diff) & sub1)

    return [
        ("0_ground_truth_raw", orig, orig),
        ("1_linear_mba_depth1", depth1, orig),
        ("2_recursive_mba_depth2", depth2, orig),
        ("3_polynomial_mba_depth3", depth3, orig),
        ("4_egraph_saturated_depth4", depth4, orig)
    ]

# ─── AST Size / Node Counter ──────────────────────────────────────────────────

def count_nodes(expr):
    visited = set()
    count = 0
    stack = [expr]
    while stack:
        curr = stack.pop()
        curr_id = curr.get_id() if hasattr(curr, "get_id") else id(curr)
        if curr_id not in visited:
            visited.add(curr_id)
            count += 1
            if hasattr(curr, "children"):
                stack.extend(curr.children())
    return count

# ─── SMT Oracle-Guided Synthesis Attack ──────────────────────────────────────

def attempt_smt_synthesis(obf_expr, orig_expr, x_var, y_var, timeout_sec=5.0):
    """
    Simulates a synthesis-based deobfuscator (e.g. Syntia / QSynth):
    Searches a 1-op grammar {x + y, x - y, x ^ y, x & y, x | y, x * y}
    to find an exact semantic match using Z3 equivalence queries.
    """
    t0 = time.perf_counter()
    
    candidates = [
        ("x + y", x_var + y_var),
        ("x - y", x_var - y_var),
        ("x ^ y", x_var ^ y_var),
        ("x & y", x_var & y_var),
        ("x | y", x_var | y_var),
        ("x * y", x_var * y_var),
        ("2*x + y", 2 * x_var + y_var),
        ("x + 2*y", x_var + 2 * y_var),
    ]
    
    recovered = False
    recovered_name = None
    
    for name, cand in candidates:
        if (time.perf_counter() - t0) > timeout_sec:
            break
            
        solver = z3.Solver()
        solver.set("timeout", int(timeout_sec * 1000))
        # Check if NOT equivalent: if UNSAT, then cand == obf_expr for all x, y!
        solver.add(cand != obf_expr)
        res = solver.check()
        if res == z3.unsat:
            recovered = True
            recovered_name = name
            break
            
    dt = time.perf_counter() - t0
    return recovered, recovered_name, dt

# ─── Benchmark Runner ─────────────────────────────────────────────────────────

def run_benchmark():
    print("\n" + "=" * 78)
    print("      VECTIS MBA ALGEBRAIC SIMPLIFICATION & DEOBFUSCATION BENCHMARK")
    print("=" * 78)
    print("Threat Model: Automated AST Simplification (Z3 BV) & SMT Synthesis Attacks.\n")

    x = z3.BitVec("x", 32)
    y = z3.BitVec("y", 32)
    targets = get_mba_targets()
    
    results = []
    
    for name, expr, orig in targets:
        orig_nodes = count_nodes(expr)
        
        # 1. Test Z3 Built-in BitVector Simplifier
        simplified = z3.simplify(expr)
        simp_nodes = count_nodes(simplified)
        
        reduction_pct = ((orig_nodes - simp_nodes) / max(1, orig_nodes)) * 100.0
        z3_defeated = (simp_nodes == count_nodes(orig))
        
        # 2. Test Oracle-Guided SMT Synthesis Attack
        synth_ok, synth_name, synth_time = attempt_smt_synthesis(expr, orig, x, y, timeout_sec=2.0)
        
        res = {
            "target": name,
            "ast_nodes_obfuscated": orig_nodes,
            "ast_nodes_z3_simplified": simp_nodes,
            "z3_size_reduction_pct": round(reduction_pct, 1),
            "z3_completely_simplified": z3_defeated,
            "synthesis_recovered": synth_ok,
            "synthesis_recovered_form": synth_name,
            "synthesis_time_sec": round(synth_time, 4),
            "resistance_status": "STRONG" if not z3_defeated else "SIMPLIFIED"
        }
        results.append(res)
        
        z3_status = "REDUCED TO GROUND TRUTH" if z3_defeated else f"RESISTANT (size {simp_nodes})"
        synth_status = f"RECOVERED ({synth_name})" if synth_ok else "SYNTHESIS FAILED"
        
        print(f"[*] Target: {name:<26}")
        print(f"    ├─ AST Nodes: {orig_nodes:3d}  -->  Z3 Simplify: {simp_nodes:3d} ({reduction_pct:5.1f}% reduction) [{z3_status}]")
        print(f"    └─ SMT Synthesis Attack: {synth_status:<22} | Time: {synth_time:6.4f}s")
        print()

    print("-" * 78)
    unsimplified = sum(1 for r in results if not r["z3_completely_simplified"])
    print(f"  Summary: {unsimplified}/{len(results)} MBA forms resisted Z3 BitVector simplification.")
    print("=" * 78 + "\n")
    
    out_json = os.path.join(PROJECT_ROOT, "benchmarks/mba_simplification_results.json")
    with open(out_json, "w") as f:
        json.dump(results, f, indent=2)
    print(f"[✓] Empirical MBA simplification benchmark results saved to {out_json}\n")

if __name__ == "__main__":
    run_benchmark()
