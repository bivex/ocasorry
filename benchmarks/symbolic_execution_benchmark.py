#!/usr/bin/env python3
"""
benchmarks/symbolic_execution_benchmark.py — Vectis SMT & Symbolic Execution Hardness Benchmark

Threat Model:
An attacker utilizes an automated SMT solver (Z3 BitVector / QF_BV / NIA engine) or symbolic execution
engine (Angr / Triton) to invert branch conditions, find license keys, or satisfy path constraints.

Evaluates 5 constraint classes:
1. Baseline Linear: Direct linear constraint (3x + 7y == 1337)
2. Degree-2 MBA: Second-order polynomial Mixed Boolean-Arithmetic
3. Degree-4 High-Order MBA: Non-linear polynomial cross-terms with bitwise masks
4. Diophantine Opaque: Quadratic Diophantine invariant (7x^2 - y^2 == 1) + bitwise entanglement
5. Rolling VKey Cascade: Multi-round stateful cryptographic key schedule constraint

Metrics:
- Time-to-Solve (T_solve in seconds, with 10.0s hard timeout)
- AST Complexity (Total Z3 BitVector node & operator count)
- State Space Explosion Factor (relative to baseline)
- Inversion Resistance Index (0..100)
"""

import time
import json
import os
import z3
import numpy as np

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TIMEOUT_MS = 10000  # 10.0s timeout per constraint

def make_solver():
    s = z3.Solver()
    s.set("timeout", TIMEOUT_MS)
    return s

# ─── Target Constraint Definitions (Z3 BitVector 32-bit) ──────────────────────

def target_1_baseline_linear():
    """Baseline: Plain linear integer equation."""
    x = z3.BitVec("x", 32)
    y = z3.BitVec("y", 32)
    constraint = (3 * x + 7 * y == 1337) & (x != y) & (x > 100)
    return "1_baseline_linear", [x, y], constraint

def target_2_degree2_mba():
    """Degree-2 MBA: (x + y)^2 represented via bitwise expansions."""
    x = z3.BitVec("x", 32)
    y = z3.BitVec("y", 32)
    # MBA expansion of x + y: ((x ^ y) + 2*(x & y))
    mba_sum = (x ^ y) + (2 * (x & y))
    # MBA expansion of x - y: ((x & ~y) - (~x & y))
    mba_diff = (x & ~y) - (~x & y)
    constraint = (mba_sum * mba_diff == 0x1337CAFE) & (x > 500)
    return "2_degree2_mba", [x, y], constraint

def target_3_high_order_mba():
    """Degree-4 Polynomial MBA with non-linear bitwise cross-terms."""
    x = z3.BitVec("x", 32)
    y = z3.BitVec("y", 32)
    z = z3.BitVec("z", 32)
    
    t1 = (x * x + 3 * y) ^ (z * 0x9E3779B9)
    t2 = ((x & y) * (y | z)) ^ (t1 * t1)
    t3 = (t2 * t1 + (x ^ z)) & 0xFFFFFFFF
    
    constraint = (t3 == 0xDEADBEEF) & (x != 0) & (y != 0) & (z != 0)
    return "3_high_order_poly_mba", [x, y, z], constraint

def target_4_diophantine_opaque():
    """Diophantine quadratic invariant entangled with bitwise masks."""
    x = z3.BitVec("x", 32)
    y = z3.BitVec("y", 32)
    
    # Invariant: 7*x^2 - y^2 == 1 has discrete solutions, combined with bitwise checks
    quad = (7 * (x * x) - (y * y))
    mask_entangle = ((x ^ 0x5A5A5A5A) + (y ^ 0xA5A5A5A5)) & 0xFFFF
    
    constraint = (quad == 1) & (mask_entangle == 0x1234) & (x > 1) & (y > 1)
    return "4_diophantine_opaque", [x, y], constraint

def target_5_rolling_vkey_cascade():
    """4-Round stateful rolling key schedule path constraint."""
    k0 = z3.BitVec("k0", 32)
    k1 = z3.BitVec("k1", 32)
    k2 = z3.BitVec("k2", 32)
    k3 = z3.BitVec("k3", 32)
    
    # Simulate dynamic rolling key evolution: K_{i+1} = ((K_i * C1) ^ (input * C2)) + C3
    s0 = (k0 * 0x9E3779B9) ^ 0xCAFEBABE
    s1 = ((s0 * 0x517CC1B7) ^ (k1 * 0x63C63CD9)) + 0x12345678
    s2 = ((s1 * 0x14057B7E) ^ (k2 * 0x5851F42D)) + 0x98765432
    s3 = ((s2 * 0x3C3C3C3C) ^ (k3 * 0xA5A5A5A5)) + 0x11223344
    
    constraint = (s3 == 0x55AA55AA) & (k0 > 10) & (k1 > 10) & (k2 > 10) & (k3 > 10)
    return "5_rolling_vkey_cascade", [k0, k1, k2, k3], constraint

# ─── AST Size / Node Counter ──────────────────────────────────────────────────

def count_ast_nodes(expr):
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

# ─── Benchmark Runner ─────────────────────────────────────────────────────────

def evaluate_constraint(name, vars_list, constraint):
    solver = make_solver()
    solver.add(constraint)
    
    ast_nodes = count_ast_nodes(constraint)
    
    t0 = time.perf_counter()
    check_res = solver.check()
    solve_time = time.perf_counter() - t0
    
    is_timeout = (check_res == z3.unknown)
    is_sat = (check_res == z3.sat)
    is_unsat = (check_res == z3.unsat)
    
    status_str = "TIMEOUT (>10.0s)" if is_timeout else ("SAT" if is_sat else "UNSAT")
    
    return {
        "target": name,
        "num_variables": len(vars_list),
        "ast_nodes": ast_nodes,
        "solve_time_sec": solve_time,
        "status": status_str,
        "is_timeout": is_timeout,
        "is_sat": is_sat
    }

def run_benchmark():
    print("\n" + "=" * 76)
    print("       VECTIS SMT & SYMBOLIC EXECUTION HARDNESS BENCHMARK")
    print("=" * 76)
    print("Threat Model: SMT Solver (Z3 QF_BV Engine) inverting path constraints.\n")

    targets = [
        target_1_baseline_linear(),
        target_2_degree2_mba(),
        target_3_high_order_mba(),
        target_4_diophantine_opaque(),
        target_5_rolling_vkey_cascade()
    ]
    
    results = []
    baseline_time = 0.001
    
    for name, vars_list, constraint in targets:
        print(f"[*] Solving constraint: {name:<26} ... ", end="", flush=True)
        res = evaluate_constraint(name, vars_list, constraint)
        results.append(res)
        
        if name == "1_baseline_linear":
            baseline_time = max(0.0001, res["solve_time_sec"])
            slowdown = 1.0
        else:
            if res["is_timeout"]:
                slowdown = (TIMEOUT_MS / 1000.0) / baseline_time
            else:
                slowdown = res["solve_time_sec"] / baseline_time
                
        res["slowdown_vs_baseline"] = round(slowdown, 1)
        
        print(f"[{res['status']:<14}] | Nodes: {res['ast_nodes']:4d} | Time: {res['solve_time_sec']:7.4f}s | Hardness: {res['slowdown_vs_baseline']:8.1f}x")

    print("-" * 76)
    timeout_count = sum(1 for r in results if r["is_timeout"])
    avg_nodes = np.mean([r["ast_nodes"] for r in results])
    
    print(f"  Summary: {timeout_count}/{len(results)} constraints exceeded SMT solver timeout (>10.0s)")
    print(f"  Average SMT BitVector AST Nodes: {avg_nodes:.1f}")
    print("=" * 76 + "\n")
    
    out_json = os.path.join(PROJECT_ROOT, "benchmarks/symbolic_execution_results.json")
    with open(out_json, "w") as f:
        json.dump(results, f, indent=2)
    print(f"[✓] Empirical SMT benchmark results saved to {out_json}\n")

if __name__ == "__main__":
    run_benchmark()
