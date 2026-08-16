<div align="center">

# 💎 Vectis

### Advanced C Source Obfuscator & Multi-VCPU Federated Virtualization Engine

[![OCaml](https://img.shields.io/badge/OCaml-5.2+-00C4B4.svg?style=for-the-badge&logo=ocaml&logoColor=white)](https://ocaml.org/)
[![CIL](https://img.shields.io/badge/AST-Goblint--CIL-028090.svg?style=for-the-badge&logo=c&logoColor=white)](https://github.com/goblint/cil)
[![ISA](https://img.shields.io/badge/Formal-Sail%20ISA-00A896.svg?style=for-the-badge)](https://github.com/rems-project/sail)
[![MLX](https://img.shields.io/badge/Neural-Apple%20MLX-20B2AA.svg?style=for-the-badge&logo=apple&logoColor=white)](docs/mlx-ai-neural-subsystem.md)
[![Target](https://img.shields.io/badge/Target-Mach--O%20%7C%20ELF%20%7C%20PE-05668D.svg?style=for-the-badge)](https://clang.llvm.org/)
[![License](https://img.shields.io/badge/License-PolyForm%20Noncommercial%201.0.0-008080.svg?style=for-the-badge)](LICENSE)

<p align="center">
  <b>Vectis</b> transforms standard C code into resilient, mathematically obfuscated C11 source code backed by per-build synthesized <b>Multi-Tier Virtual Processors (VCPUs)</b>, <b>Apple MLX Neural Synthesis</b>, <b>Native AArch64 Machine Code JIT Backend</b>, <b>In-VM Ephemeral JIT Escape Gates</b>, <b>E-Graph Equality MBA</b>, and <b>66+ military-grade protection passes</b>.
</p>

---

</div>

## 💠 Core Architectural Pillars

* 🔷 **Federated 4-Tier VCPU Cascade**: Vector `random_vISA` (with In-VM JIT Escape Gates), 2-tier `NestedVM`, stateful `RollingVKey`, and in-memory `EphemeralJIT` (powered by a native AArch64 machine code compiler).
* ⚡ **In-VM Dynamic JIT Escape Gates (`VJIT`)**: Hybrid virtual machine architecture that dynamically compiles and executes native machine code on host CPU hardware mid-interpretation, wiping pages via 3-pass DoD 5220.22-M routines.
* 🧠 **Apple MLX Neural Subsystem**: PPO RL agent on Metal GPU for real-time MBA synthesis + 3-Level Z3 SMT formal verification.
* 🧬 **Multi-ISA per-Function Routing**: Compile different C functions into completely distinct, randomized virtual processor architectures within the same binary.
* 🌌 **E-Graph MBA Expansion**: Infinite non-linear bitwise identities generated via e-graph equality saturation (*arXiv:2603.03624*).
* 🛡️ **Anti-Decompiler Hardening**: Overlapping aliased register matrix (`__vbank`), Loki algebraic invariants (*arXiv:2106.08913*), VPC path constraints (*arXiv:2603.18355*), and ABI EH shadowing (*arXiv:2601.10261*).
* ⚡ **Drop-in Compiler Toolchain**: Seamless `vectis-cc` compiler wrapper for transparent integration with `make`, `cmake`, and `ninja`.

---

## 📑 Documentation Hub

| Document | Topic & Focus |
| :--- | :--- |
| 🏛️ **[Architecture](docs/architecture.md)** | Hexagonal layer design, Entities, Ports (SPI), Domain Services |
| ⚡ **[Virtual ISA v2](docs/vm-isa.md)** | 18 typed opcodes, condition flags (ZF, NF, CF, VF), state masking, steppers |
| 🧠 **[Neural Rewriter & E-Graph](docs/neural-rewriter.md)** | E-graph equality saturation, verified MBA rules, candidate generator, SMT |
| 🛡️ **[Security Model & Threats](docs/security-model.md)** | Threat classes, state masking, Anti-Pushan invariant, DoD 5220.22-M wipe |
| 📦 **[SDK & CLI Guide](docs/sdk.md)** | Python SDK API (`VectisCompiler`), YAML configuration, `bin/vectis_cli.py` |
| 📈 **[Benchmarks & Metrics](docs/benchmarks.md)** | TPDI Grade A (75.00), Black-box resistance (98.88%), 70 test suites |
| 🔨 **[Build & Developer Guide](docs/build.md)** | Prerequisites, OCaml 5 + Dune, test runners, ML pipeline integration |
| 🧠 **[MLX Neural Engine & AI](docs/mlx-ai-neural-subsystem.md)** | Apple Silicon MLX models, PPO synthesis, dataset gen, Z3 SMT verifier |
| 🛡️ **[4-VCPU Virtualization](docs/4-vcpu-federated-virtualization.md)** | 4-Tier VCPU cascade, formal Sail specifications, keygen solver |
| 🧬 **[ISA Pipeline](docs/isa-generation-pipeline.md)** | End-to-end guide: Sail/JSON synthesis to target C11 runtime |
| 🗝️ **[License Keygen](docs/license-keygen.md)** | Meet-in-the-middle solver, cascade math, Python & C keygen tools |
| 🌀 **[Virtualization & vISA](docs/virtualization-and-random-visa.md)** | Synthetic vector ISA, nested VM, self-modifying bytecode, JIT |
| ⚡ **[Obfuscation Passes](docs/obfuscation-passes.md)** | Complete theoretical and mathematical reference for all 61+ passes |
| 🔄 **[Two-Level JIT & Signals](docs/two-tier-jit.md)** | Staging engine, Apple Silicon W^X cache, `ucontext_t` PC redirection |
| 🛠️ **[Compiler Wrapper](docs/compiler-wrapper.md)** | `vectis-cc` integration for CMake, Makefiles, and build scripts |
| 📋 **[CIL Capabilities](docs/cil-capabilities.md)** | Checkbox roadmap of all implemented features via Goblint-CIL |


---

## 🔷 4-Tier Virtual Processor Hierarchy

```mermaid
graph LR
    subgraph "Federated Virtual Processor Cascade"
        IN["Input Seed"] --> V1["Tier 1: random_vISA\n(Vector 32-bit RISC)"]
        V1 --> V2["Tier 2: NestedVM\n(2-Tier Hierarchy)"]
        V2 --> V3["Tier 3: RollingVKey\n(Stateful Key Chain)"]
        V3 --> V4["Tier 4: EphemeralJIT\n(In-Memory Self-Wiping JIT)"]
        V4 --> OUT["Verified State / Execution"]
    end
    style V1 fill:#00C4B4,stroke:#028090,color:#fff
    style V2 fill:#00A896,stroke:#028090,color:#fff
    style V3 fill:#028090,stroke:#05668D,color:#fff
    style V4 fill:#05668D,stroke:#013a63,color:#fff
```

| Tier | Engine | Granular Annotation | Output Specification |
| :---: | :--- | :--- | :--- |
| **1** | `random_vISA` | `__attribute__((annotate("vectis:visa:ArchName")))` | [`vcpu1_visa.sail`](examples/optimal_license_sail/vcpu1_visa.sail) |
| **2** | `nested_vm` | `__attribute__((annotate("vectis:nested_vm")))` | [`vcpu2_nested_vm.sail`](examples/optimal_license_sail/vcpu2_nested_vm.sail) |
| **3** | `rolling_vkey` | `__attribute__((annotate("vectis:rolling_vkey")))` | [`vcpu3_rolling_vkey.sail`](examples/optimal_license_sail/vcpu3_rolling_vkey.sail) |
| **4** | `ephemeral_jit` | `__attribute__((annotate("vectis:ephemeral")))` | [`vcpu4_ephemeral_jit.sail`](examples/optimal_license_sail/vcpu4_ephemeral_jit.sail) |

---

## ✨ Key Capabilities at a Glance

| Category | Highlights | Key Passes |
| :--- | :--- | :--- |
| 🌀 **Virtualization** | Custom per-build ISAs, direct-threading computed gotos, S-box traps | `Virtualize`, `NestedVM`, `RollingVKey`, `SelfModVM`, `DecentDisp` |
| 🔀 **Control Flow** | Irreducible CFG loops, Diophantine predicates, basic block jittering | `CFF`, `IrreducibleCFG`, `BCF`, `BBSplit`, `LoopToRecursion`, `IndirectJump` |
| 🔢 **Data & Math** | High-order non-linear polynomial MBA, fixed-scale float MBA, variable splitting | `EGraphMBA`, `PolynomialMBA`, `FloatMBA`, `EncodeData`, `LUT`, `Homomorphic` |
| 🛡️ **Anti-Analysis** | Memory aliasing to defeat VTIL/NoVmp, ABI exception shadowing, anti-debug | `AntiVTIL`, `EHShadow`, `LokiInvariants`, `AntiDebug`, `TimingCheck`, `APIHash` |

---

## ⚡ Quick Start & Makefile Recipes

### 1. Build the Toolchain
```bash
eval $(opam env)
dune build
```

### 2. Full 4-Tier Virtualization in 1 Command
```bash
# Obfuscates and compiles with full 4-VCPU cascade & ML-optimized vISA spec
make virtualize IN=target.c BIN=target.bin
./target.bin
```

### 3. Run the Complete AI Neural Pipeline
```bash
# Dataset generation -> Deep Ensemble -> VCPU Architect -> PPO Synthesis -> Z3 Verification
make ml-pipeline
```

### 4. Custom Granular CLI Obfuscation
```bash
vectis -i target.c -o target.obf.c \
  --visa-spec examples/ml_optimized/visa.json \
  --vm-profile fortress-256k \
  --virtualize \
  --rolling-vkey \
  --egraph-mba \
  --loki-invariants \
  --anti-vtil
```

---

## 🛠️ Transparent Compiler Wrapper (`vectis-cc`)

Use `vectis-cc` as a drop-in replacement for `gcc` or `clang` in existing build systems:

```bash
export CC=vectis-cc
export CFLAGS="--vectis-virtualize --vectis-egraph-mba --vectis-anti-vtil"
make
```

---

<div align="center">

<sub>Engineered with 💎 by the Vectis Team. Free for Noncommercial / Public use. Commercial use requires author's consent (<a href="LICENSE">PolyForm Noncommercial 1.0.0</a>).</sub>

</div>
