# OcaSorry

**OcaSorry** is an advanced, multi-target code obfuscator and multi-tier native JIT execution engine written in **OCaml 5**, designed following **Domain-Driven Design (DDD)** and **Hexagonal Architecture (Ports & Adapters)**.

It combines **C Source-to-Source AST transformations** (powered by George Necula's [CIL / Goblint-CIL](https://github.com/cil-project/cil)) with a **Two-Level JIT Engine**, a **drop-in compiler wrapper (`ocasorry-cc`)**, a **native AArch64 (ARM64 / Apple Silicon) machine code emitter**, and an **ECMA-335 CIL bytecode VM**.

---

## 📚 Documentation Index

Detailed technical documentation is available in the [`docs/`](file:///Volumes/External/Code/ocasorry/docs/) directory:

- 🏛️ **[Hexagonal Architecture & DDD](file:///Volumes/External/Code/ocasorry/docs/architecture.md)**: Layer partitioning, Entities, Ports (SPI), and Domain Services.
- 🌀 **[Polymorphic Virtualization & random_vISA](file:///Volumes/External/Code/ocasorry/docs/virtualization-and-random-visa.md)**: Per-build synthetic vector ISA, nested multi-layer VM, self-modifying bytecode, and JIT compilation.
- ⚡ **[Obfuscation Passes & Math](file:///Volumes/External/Code/ocasorry/docs/obfuscation-passes.md)**: MBA identities, Control Flow Flattening, Opaque Predicates, `EncodeLiterals`, `EncodeData` (Variable Splitting), Function Merging/Outlining, and C Implicit Flow.
- 🔄 **[Two-Level JITting & Hardware Signal Flow](file:///Volumes/External/Code/ocasorry/docs/two-tier-jit.md)**: Staging architecture, Apple Silicon W^X cache management, and `ucontext_t` PC redirection.
- 🛠️ **[Compiler Wrapper (`ocasorry-cc`)](file:///Volumes/External/Code/ocasorry/docs/compiler-wrapper.md)**: Integration guide for Makefiles, CMake, flags, and options.
- 📋 **[CIL Capabilities & Obfuscation Roadmap](file:///Volumes/External/Code/ocasorry/docs/cil-capabilities.md)**: Complete checkbox roadmap of all feasible techniques via George Necula's CIL / Goblint-CIL.

---

## 🎯 Why OCaml + CIL Instead of LLVM?

| Problem with LLVM | Advantage of OCaml + CIL (`OcaSorry`) |
| :--- | :--- |
| **Normalizing IR**: LLVM IR canonicalizes control flow, unfolds opaque predicates, and removes dead code. | **AST Preservation**: CIL AST preserves intentional entropy, dead branches, and complex structures without optimization passes un-obfuscating them. |
| **Heavy Dependency**: LLVM requires massive toolchains (hundreds of MBs/GBs). | **Lightweight & Fast**: Pure OCaml with algebraic data types, pattern matching, and minimal runtime footprint. |
| **Hardware Tricks**: Difficult to execute signal traps and custom inline dispatchers. | **Full Low-Level Control**: Native support for signal handlers (`SIGSEGV`/`SIGTRAP`), custom `mmap(MAP_JIT)` execution, and raw byte-level assembly synthesis. |

---

## ⚡ Key Capabilities

1. **Two-Level JITting + Hardware Implicit Flow**: Compact outer stager triggers hardware fault (`BRK`), signal handler dynamically decrypts inner payload and updates CPU `PC` register directly.
2. **High-Order Polynomial MBA (Anti-Z3)**: Non-linear polynomial expressions and invertible affine layers over $\mathbb{Z}_{2^{32}}$.
3. **Function Merging & Outlining**: Inter-procedural merging (`--ocasorry-merge`) and basic-block slicing (`--ocasorry-outline`).
4. **Variable Splitting & Data Encoding (`EncodeData`)**: Splits scalar variables into multiple components maintaining mathematical invariants.
5. **Control Flow Flattening (CFF)**: Flattens function control flow into a state-machine switch dispatcher.
6. **Invariant Opaque Predicates**: Injects algebraic tautologies (`(x & ~x) == 0`) with deceptive dead branches.
7. **EncodeLiterals (String Encryption)**: Encrypts static strings into byte arrays with lazy in-function runtime decryptors.
8. **C-Level Implicit Flow**: Converts conditional branches into `NULL` pointer dereferences caught via signals.
9. **Drop-in Compiler Wrapper (`ocasorry-cc`)**: Seamless build integration (`CC=ocasorry-cc make`).

---

## 🚀 Quick Start

### Build Everything
```bash
dune build
```

### Run Multi-Target Demo
```bash
dune exec ./bin/main.exe
```

### Run Automated Test Suites
```bash
dune runtest
```

### Build and Run C Examples
```bash
make -C examples CC=../_build/default/bin/ocasorry_cc.exe run
```

---

## 📄 License

MIT License.
