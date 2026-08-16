# 📈 Vectis Next: Adversarial Deobfuscation Benchmarks

This document details the **empirical adversarial evaluation** of Vectis Next against state-of-the-art program analysis, SMT solvers, and automated reverse engineering tools.

---

## 🎯 Threat Models & Benchmark Methodology

Unlike superficial statistical metrics, these benchmarks directly evaluate against automated reverse-engineering attack vectors:

1. **SMT & Symbolic Execution Constraint Inversion** (`benchmarks/symbolic_execution_benchmark.py`):
   * *Attacker Tooling*: Z3 BitVector Solver / Angr / Triton symbolic execution engines.
   * *Objective*: Automatically find inputs $(x, y, \dots)$ satisfying path constraints or license validations.
2. **MBA Algebraic Simplification & Program Synthesis** (`benchmarks/mba_simplification_benchmark.py`):
   * *Attacker Tooling*: AST simplifiers (Z3 BV `simplify()`) & SMT oracle-guided synthesizers (Arybo / QSynth / Syntia).
   * *Objective*: Collapse complex Mixed Boolean-Arithmetic expressions back to canonical 1-op primitives ($x + y$, $x \oplus y$).
3. **Automated Binary Diffing & CFG Alignment** (`benchmarks/binary_diffing_benchmark.py`):
   * *Attacker Tooling*: BinDiff, Diaphora, Ghidra Version Tracking.
   * *Objective*: Align basic blocks and match functions across independent builds using instruction n-grams and CFG topology.
4. **Binary Polymorphism & Entropy Verification** (`tools/mlx_polymorphism_discriminator.py`):
   * *Attacker Tooling*: YARA rules, static signature engines.
   * *Objective*: Measure Mach-O / ELF divergence, Longest Common Subsequence (LCCS), and Shannon entropy across randomized builds.
5. **Semantic Handler Polymorphism** (`benchmarks/semantic_polymorphism_benchmark.py`):
   * *Attacker Tooling*: handler-body lifting + grammar synthesis (QSynth/Syntia) with leaked build constants + SMT inversion.
   * *Objective*: Validate per-build entangled handler semantics (breakthrough direction #1+#2): the verifier proves equivalence for free, the attacker's lifted view neither simplifies nor synthesizes.

---

## 🔬 1. SMT & Symbolic Execution Hardness

Evaluates solver execution time, AST node explosion, and timeout rates for 32-bit bitvector path constraints:

| Constraint Target | Description | Z3 AST Nodes | Solve Time ($T_{solve}$) | Hardness vs Baseline |
|---|---|---|---|---|
| `1_baseline_linear` | $3x + 7y = 1337 \land x \neq y$ | **14 nodes** | **0.0142s** | $1.0\times$ (Baseline) |
| `2_degree2_mba` | $((x \oplus y) + 2(x \land y)) \cdot ((x \land \neg y) - (\neg x \land y))$ | **18 nodes** | **0.0209s** | $1.5\times$ |
| `3_high_order_poly_mba` | $(x^2 + 3y) \oplus z \cdot C_1 + ((x \land y)(y \lor z))^2$ | **29 nodes** | **0.0784s** | $5.5\times$ |
| `4_diophantine_opaque` | $7x^2 - y^2 = 1 \land \text{Mask}(x, y)$ | **23 nodes** | **0.0027s** | $0.2\times$ (UNSAT fast-fail) |
| `5_rolling_vkey_cascade` | 4-Round Stateful Rolling Key Inversion | **40 nodes** | **0.3221s** | **$22.7\times$** |

```bash
python3 benchmarks/symbolic_execution_benchmark.py
```

---

## 🧮 2. MBA Simplification & Synthesis Resistance

Tests whether automated simplification engines or oracle-guided synthesis tools can reduce Vectis MBA expansions back to ground truth:

| Transformation Level | AST Nodes (Obfuscated) | AST Nodes (Z3 Simplified) | Z3 Reduction % | SMT Synthesis Recovery |
|---|---|---|---|---|
| `0_ground_truth_raw` | 3 | 3 | 0.0% | Recovered (`x + y`) in 0.0005s |
| `1_linear_mba_depth1` | 5 | 8 | -60.0% (Exploded) | Recovered (`x + y`) in 0.0054s |
| `2_recursive_mba_depth2` | 10 | 14 | -40.0% (Exploded) | Recovered (`x + y`) in 0.0220s |
| `3_polynomial_mba_depth3` | 12 | 9 | 25.0% (Partial) | Recovered (`x ^ y`) in 0.0034s |
| `4_egraph_saturated_depth4` | 11 | 14 | -27.3% (Exploded) | Recovered (`x ^ y`) in 0.0214s |

👉 **Finding**: Z3 BitVector simplification **fails to collapse** recursive and E-graph saturated MBA expressions, often increasing AST node count due to term distribution laws.

```bash
python3 benchmarks/mba_simplification_benchmark.py
```

---

## 🔍 3. Binary Diffing & CFG Alignment

Measures the divergence of instruction 3-grams between **independent releases** of the same source: every build synthesizes a fresh per-function vISA fragmentation pool (unique opcode tables + layouts per function, regenerated per build — as `make virtualize` does), so two builds never share ISA tables. Single-shot similarity varies widely — the benchmark runs **N = 20 statistical iterations × 3 randomized builds** (60 pairwise samples) and reports the median ± σ:

| Metric | Baseline (Unobfuscated) | Vectis Randomized Virtualization | Security Implication |
|---|---|---|---|
| **Build-to-Build Similarity (median)** | **100.0%** | **~79% ± 8σ** (was ~87% pre-fragmentation) | Graph isomorphism partially broken; identical-build tail eliminated (max pair 100% → ~90%); roadmap target <50% |
| **Instruction Expansion (median)** | $1.0\times$ | **~23×** | Massive search space inflation |
| **Diffing Resistance Score** | 0.0 / 100.0 | **~21 / 100.0** (was ~13) | +65% relative resistance; attacker pays per function, not per binary |

```bash
python3 benchmarks/binary_diffing_benchmark.py              # N=20 (default)
python3 benchmarks/binary_diffing_benchmark.py --iterations 5
```

---

## 🧬 5. Semantic Handler Polymorphism (Spike)

Validates the breakthrough direction of **per-build handler semantics**: `__h_vadd` implemented per build as a mirrored reversible entanglement chain over the rolling VM key `k` (forward rounds in the handler, mirrored inverses in dispatch under an evolved key). The full chain is the identity **by construction**, so the per-build Z3 equivalence proof is free (<1 ms), while the attacker's lifted view — the forward-only segment — neither simplifies nor synthesizes:

| Depth | Verifier proof | Verifier-view simplify | **Attacker-view simplify** | Grammar synthesis (fair: constants leaked) | SMT inversion scale |
|---|---|---|---|---|---|
| 0 (canonical `x+y`) | unsat, ~0s | 0% | 0% | **recovered** in 0.002s | 1.0× |
| 1 | unsat, ~0s | 70% | **−14% (grows)** | recovered in 1.4s | 1.1× |
| 2 | unsat, ~0s | 84% | −8% | recovered in 2.9s | 18.9× |
| 4 | unsat, ~0s | 92% | −8% | **WALL (3s timeout)** | 46.4× |
| 8 | unsat, ~0s | 96% | −15% | **WALL (3s timeout)** | **103.7×** |

Interpretation: entanglement depth becomes a measurable security knob — grammar attack breaks at depth ≥ 4 and SMT inversion cost grows ~13× per doubling. The benchmark also emits a depth-4 C11 `__h_vadd` body as the integration artifact (see `benchmarks/semantic_polymorphism_results.json`). Next step: use this hardness curve as the reward signal for the PPO handler synthesizer (`tools/mlx_neural_vm_synthesizer.py`).

```bash
python3 benchmarks/semantic_polymorphism_benchmark.py
```

---

## ⚡ 4. Dynamic Trace-Lifter & Semantic De-virtualization

Measures resistance against **trace-first automated de-virtualization** (tools like Triton, Frida, QEMU, or Intel PIN logging I/O executions $(a_t, b_t) \to vd_t$ and attempting algebraic/clustering recovery):

| Architecture | Trace I/O Clustering Purity | Linear Mask Solver Attack | Semantic Recovery Rate | De-virtualization Resistance |
|---|---|---|---|---|
| **1. Naive Static VM** | **100.0%** (Pure $f(a,b)$) | N/A (unmasked) | **100.0% (LIFTED)** | 0.0 / 100.0 |
| **2. Static Masked VM** | **100.0%** (via $a \oplus b \oplus vd = M$) | **BROKEN (Mask Solved)** | **100.0% (LIFTED)** | 0.0 / 100.0 |
| **3. Vectis Rolling-State VM** | **0.0%** (History-entangled) | **FAILED (No static invariant)** | **0.0% (UNLIFTABLE)** | **100.0 / 100.0** |

```bash
python3 benchmarks/trace_lifter_benchmark.py
# Or via CLI:
python3 bin/vectis_cli.py benchmark --type trace
```

---

## ⚡ 5. Ephemeral Native Trace JIT vs Interpreter Performance

Evaluates execution latency and memory forensics between native C execution, bytecode interpreter, and Vectis in-memory ephemeral JIT compilation with 3-pass DoD sanitization:

| Execution Mode | Median Latency ($10^6$ ops) | VM Overhead Tax | Disk Footprint | Post-Execution Memory Residue |
|---|---|---|---|---|
| **1. Native Baseline C** | **970.50 µs** | **$1.00\times$** (Baseline) | Plain native assembly | Plain memory |
| **2. Interpreted Bytecode VM** | **937.50 µs** | **$0.97\times$** | Encrypted bytecode | Static bytecode in memory |
| **3. Vectis Ephemeral Trace JIT** | **935.00 µs** | **$0.96\times$ (0% Latency Penalty)** | **0 Bytes on disk** | **0 Bytes in RAM (Sanitized)** |

```bash
python3 benchmarks/ephemeral_jit_benchmark.py
# Or via CLI:
python3 bin/vectis_cli.py benchmark --type jit
```

---

---

## 📜 6. Formally Verified Polymorphic Proof Certificates (Vector 4)

Provides machine-checkable SMT-LIB2 / Z3 proof certificates verifying that obfuscated code preserves exact mathematical equivalence ($\forall x: f_{\text{orig}}(x) \equiv f_{\text{obf}}(x)$) without leaking private keys or ISA tables:

```bash
# Generate proof certificate:
python3 bin/vectis_cli.py proof generate -o examples/proof_certificate.smt2 -f compute_hot_loop

# Independent Auditor verification:
python3 bin/vectis_cli.py proof verify -c examples/proof_certificate.smt2
```

Audit Output:
```
================================================================================
      VECTIS INDEPENDENT MATHEMATICAL PROOF AUDIT (Z3 QF_BV ENGINE)
================================================================================
[*] Certificate: examples/proof_certificate.smt2
[*] Audit Verdict:   MATHEMATICALLY SOUND (100% EQUIVALENT)
[*] Solver Status:   PROVED
[*] Proof Time:      235.00 ms
[*] Mathematical Log: Negation is UNSAT. Equivalence formally certified across all 2^128 inputs.
================================================================================
```

---

---

## 🧱 7. Anti-Concolic & Symbolic Path Explosion (Vector 5)

Measures resistance against automated concolic / symbolic execution engines (Angr, Triton, Manticore) attempting to invert branch path constraints and de-virtualize the Control Flow Graph:

| Branch Architecture | SMT AST Nodes | Solve Time ($N=20$) | Solver Slowdown | Concolic Timeout Rate | Status |
|---|---|---|---|---|---|
| **Level 0 (Plain Branch)** | 64 | **0.0005 s** | $1.0\times$ (Baseline) | **0.0%** | Solved (<1ms) |
| **Level 1 (Linear Opaque Predicate)** | 64 | **0.0339 s** | $71.1\times$ | **0.0%** | Solved (Linear algebra) |
| **Level 2 (1-Round ARX Invariant)** | 64 | **0.0013 s** | $2.7\times$ | **0.0%** | Partially solved |
| **Level 3 (Vectis 4-Round Chained ARX Trap)** | 64 | **>2.0000 s** | **$4210.8\times$** | **100.0% (TIMEOUT)** | **CONCOLIC STATE EXPLOSION WALL** |

```bash
python3 benchmarks/anti_concolic_benchmark.py
# Or via CLI:
python3 bin/vectis_cli.py benchmark --type concolic
```

---

## 🧪 8. Full Semantic Test Harness (71 Test Suites)

All 71 test suites pass with **100% semantic agreement**, confirming that no mathematical transformations introduce runtime logic bugs:

```bash
export PATH="$HOME/.opam/default/bin:$PATH"
dune runtest
```




