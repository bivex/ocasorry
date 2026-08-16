# 🔨 Vectis Next: Build & Developer Guide

Instructions for building, testing, and developing within the **Vectis Next** ecosystem.

---

## 📋 1. Prerequisites

- **macOS** (Apple Silicon recommended for MLX acceleration)
- **OCaml 5.x** with OPAM (`opam switch 5.1.0`)
- **Dune 3.x** (`opam install dune goblint-cil ounit2 z3`)
- **Clang / LLVM 15+**
- **Python 3.10+** (`pip install mlx numpy pyyaml z3-solver`)

---

## 🚀 2. Building the Project

Ensure the OPAM binary environment is active:

```bash
export PATH="$HOME/.opam/default/bin:$PATH"
dune build
```

This compiles:
- `_build/default/bin/main.exe` — Core C source obfuscator & virtualizer
- `_build/default/bin/vectis_cc.exe` — Compiler wrapper
- `_build/default/bin/ocasorry_synth.exe` — Sail ISA synthesizer & code generator
- `_build/default/lib/vectis_lib.cma` — Modular library

---

## 🧪 3. Running Test Suites

Run all **70 modular test suites** (AArch64 JIT, CIL, Tigress passes, vISA, VM Interpreter, E-Graph, Neural Rewriter):

```bash
export PATH="$HOME/.opam/default/bin:$PATH"
dune runtest
```

---

## 🤖 4. Running ML & Neural Pipelines

```bash
# 1. Evaluate Polymorphism Discriminator (Grade A verification)
python3 tools/mlx_polymorphism_discriminator.py --test

# 2. Run Black-Box Behavior Model Benchmark
python3 benchmarks/blackbox_behavior_benchmark.py

# 3. Formally verify Sail ISA specifications
python3 tools/mlx_neural_sail_verifier.py examples/

# 4. Generate Neural Rewriter training dataset
python3 tools/neural_dataset_gen.py -n 1000
```
