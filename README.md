# OcaSorry

**OcaSorry** is an advanced, multi-target code obfuscator and multi-tier native JIT execution engine written in **OCaml 5**, designed following **Domain-Driven Design (DDD)** and **Hexagonal Architecture (Ports & Adapters)**.

It combines **C Source-to-Source AST transformations** (powered by George Necula's [CIL / Goblint-CIL](https://github.com/cil-project/cil)) with a **Two-Level JIT Engine**, a **drop-in compiler wrapper (`ocasorry-cc`)**, a **native AArch64 (ARM64 / Apple Silicon) machine code emitter**, and an **ECMA-335 CIL bytecode VM**.

---

## 📚 Documentation Index

Detailed technical documentation is available in the [`docs/`](file:///Volumes/External/Code/ocasorry/docs/) directory:

- 🏛️ **[Hexagonal Architecture & DDD](file:///Volumes/External/Code/ocasorry/docs/architecture.md)**: Layer partitioning, Entities, Ports (SPI), and Domain Services.
- ⚡ **[Obfuscation Passes & Math](file:///Volumes/External/Code/ocasorry/docs/obfuscation-passes.md)**: MBA identities, Control Flow Flattening, Opaque Predicates, `EncodeLiterals`, `EncodeData` (Variable Splitting), and C Implicit Flow.
- 🔄 **[Two-Level JITting & Hardware Signal Flow](file:///Volumes/External/Code/ocasorry/docs/two-tier-jit.md)**: Staging architecture, Apple Silicon W^X cache management, and `ucontext_t` PC redirection.
- 🛠️ **[Compiler Wrapper (`ocasorry-cc`)](file:///Volumes/External/Code/ocasorry/docs/compiler-wrapper.md)**: Integration guide for Makefiles, CMake, flags, and options.

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
2. **Variable Splitting & Data Encoding (`EncodeData`)**: Splits scalar variables into multiple components maintaining mathematical invariants across reads/writes.
3. **Mixed Boolean-Arithmetic (MBA)**: Rewrites arithmetic into non-linear boolean polynomial identities.
4. **Control Flow Flattening (CFF)**: Flattens function control flow into a state-machine switch dispatcher.
5. **Invariant Opaque Predicates**: Injects algebraic tautologies (`(x & ~x) == 0`) with deceptive dead branches.
6. **EncodeLiterals (String Encryption)**: Encrypts static strings into byte arrays with lazy in-function runtime decryptors.
7. **C-Level Implicit Flow**: Converts conditional branches into `NULL` pointer dereferences caught via signals and routed with `sigsetjmp`/`siglongjmp`.
8. **Drop-in Compiler Wrapper (`ocasorry-cc`)**: Seamless build integration (`CC=ocasorry-cc make`).

---

## 🚀 Quick Start

### Prerequisites
- **OCaml** >= 5.0.0, **Dune** >= 3.10
- **Opam package**: `goblint-cil`
- **C Compiler**: `clang` or `gcc`

```bash
opam install goblint-cil dune -y
```

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

---

## 📄 License

MIT License.
