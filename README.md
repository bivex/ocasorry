# OcaSorry

**OcaSorry** is an advanced, multi-target code obfuscator and native JIT execution engine written in **OCaml 5**, designed following **Domain-Driven Design (DDD)** and **Hexagonal Architecture (Ports & Adapters)**.

It combines **C Source-to-Source AST transformations** (powered by George Necula's [CIL / Goblint-CIL](https://github.com/cil-project/cil)) with a **drop-in compiler wrapper (`ocasorry-cc`)**, a **native AArch64 (ARM64 / Apple Silicon) machine code JIT emitter**, and an **ECMA-335 CIL bytecode VM**.

---

## 🎯 Why OCaml + CIL Instead of LLVM?

While LLVM is standard for general-purpose compilation, it has fundamental drawbacks when building high-resilience obfuscators:

| Problem with LLVM | Advantage of OCaml + CIL (`OcaSorry`) |
| :--- | :--- |
| **Normalizing IR**: LLVM IR constantly canonicalizes control flow, unfolds opaque predicates, and removes dead code. | **AST Preservation**: CIL AST preserves intentional entropy, dead branches, and complex structures without optimization passes un-obfuscating them. |
| **Heavy Dependency**: LLVM requires massive toolchains (hundreds of MBs/GBs). | **Lightweight & Fast**: Pure OCaml with algebraic data types, pattern matching, and minimal runtime footprint. |
| **Hardware Tricks**: Difficult to execute signal traps, self-modifying code, and custom inline dispatchers. | **Full Low-Level Control**: Native support for signal handlers (`SIGSEGV`/`sigsetjmp`), custom `mmap(MAP_JIT)` execution, and raw byte-level assembly synthesis. |

---

## 🏛️ Hexagonal Architecture (Ports & Adapters)

```
                       ┌────────────────────────────────────────────────────────┐
                       │                   DRIVING / INBOUND                    │
                       │     [ CLI: ocasorry | ocasorry-cc | Test Suites ]      │
                       └──────────────────────────┬─────────────────────────────┘
                                                  │
                                                  ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ APPLICATION LAYER (Use Cases & Pipeline Orchestration)                                                  │
│  • Obfuscate_c_source_usecase  (Source-to-Source C Transformations)                                     │
│  • Jit_runner_usecase          (Binary JIT Compilation & Native Execution)                              │
│                                                                                                         │
│  ┌───────────────────────────────────────────────────────────────────────────────────────────────────┐  │
│  │ DOMAIN CORE (Pure, Zero-Dependency Business Logic)                                                │  │
│  │                                                                                                   │  │
│  │  [ Value Objects & Entities ]                                                                     │  │
│  │    • Reg (X0..X30, SP), Imm, Condition, Label, Instruction AST, BasicBlock, CFG                  │  │
│  │                                                                                                   │  │
│  │  [ Domain Transformation Services ]                                                               │  │
│  │    • Mba_service / C_mba_service                     (Mixed Boolean-Arithmetic)                  │  │
│  │    • Flattening_service / C_flattening_service       (Control Flow Flattening)                   │  │
│  │    • Opaque_predicate_service / C_opaque_service     (Invariant Injections)                      │  │
│  │    • C_encode_literals_service                       (String Encryption & Lazy Decryptors)       │  │
│  │    • C_implicit_flow_service                         (Signal/Exception-driven Jumps)             │  │
│  │    • C_encode_data_service                           (Variable Splitting & Data Encoding)        │  │
│  │                                                                                                   │  │
│  │  [ Driven Ports (Interfaces / SPI) ]                                                              │  │
│  │    • C_source_port.S        • Encoder_port.S                                                      │  │
│  │    • Executor_port.S        • Entropy_port.S                                                      │  │
│  └───────────────────────────────────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────┬───────────────────────────────────────────────────────────────┘
                                          │
                                          ▼
                       ┌────────────────────────────────────────────────────────┐
                       │                   DRIVEN / OUTBOUND                    │
                       │  • Goblint_cil_adapter      (C_source_port)            │
                       │  • Aarch64_encoder_adapter  (Encoder_port)             │
                       │  • Cil_encoder_adapter      (Encoder_port)             │
                       │  • Posix_mmap_adapter       (Executor_port + C-FFI)    │
                       │  • Cil_vm_adapter           (Executor_port)            │
                       │  • System_entropy_adapter   (Entropy_port)             │
                       └────────────────────────────────────────────────────────┘
```

---

## ⚡ Supported Obfuscation Techniques

### 1. Variable Splitting & Data Encoding (`EncodeData`)
- Splits eligible local scalar variables $v$ into multiple variables $(v_{s1}, v_{s2})$.
- Invariant maintenance: $v = v_{s1} + v_{s2}$ across all reads and writes.
- Write assignments $v = \text{expr}$ decompose into:
  $$\text{temp} = \text{expr}, \quad v_{s2} = \text{temp} \gg 1, \quad v_{s1} = \text{temp} - (\text{temp} \gg 1)$$
- Completely hides variable values from memory scanners and symbolic executors.

### 2. Mixed Boolean-Arithmetic (MBA)
Transforms standard arithmetic (`+`, `-`, `^`) into non-linear boolean identities:
- $x + y \iff (x \oplus y) + 2(x \land y)$
- $x + y \iff (x \lor y) + (x \land y)$
- $x + y \iff 2(x \lor y) - (x \oplus y)$
- $x - y \iff (x \oplus y) - 2(\sim x \land y)$
- $x \oplus y \iff (x \lor y) - (x \land y)$

### 3. Control Flow Flattening (CFF)
Flattens structured logic (loops, branches, sequential statements) into a state-machine switch dispatcher (`__cff_state`) with randomized case ordering.

### 4. Invariant Opaque Predicates
Injects mathematically invariant conditions:
- $(x \land \sim x) = 0$ (Always zero for any integer)
- Dead branches filled with invalid opcodes, deceptive instructions, or trap stubs that are never executed at runtime.

### 5. EncodeLiterals (String Encryption)
- Automatically intercepts all string literals `Const (CStr "...")`.
- Replaces strings with encrypted static byte arrays `static char __enc_lit_X[]` using generated keys.
- Inserts lazy inline decryptor guards into function prologues, leaving zero plain-text strings in binary `.rodata`.

### 6. Implicit Flow (Signal / Exception Driven Dispatch)
- Replaces explicit conditional branches `if (cond) { A } else { B }` with hardware signal traps.
- Sets a global handler for `SIGSEGV` and checkpoints execution via `sigsetjmp`.
- If condition is true, dereferences `NULL` (`*(volatile int*)0 = 42`), causing a signal trap that jumps directly to the target block via `siglongjmp`.

### 7. Native AArch64 JIT Memory Engine
- Emits raw 32-bit ARM64 machine instructions (little-endian byte streams).
- Resolves PC-relative branch targets dynamically.
- Allocates executable memory via `mmap(MAP_JIT)` with full Apple Silicon W^X protection management (`pthread_jit_write_protect_np(0/1)`) and instruction cache flush (`sys_icache_invalidate`).

---

## 🛠️ Drop-in Compiler Wrapper (`ocasorry-cc`)

`ocasorry-cc` acts as a drop-in replacement for `clang` or `gcc` in any Makefile, CMake, or build script:

```bash
# Compile project with full obfuscation transparently:
CC=ocasorry-cc make

# Or invoke directly:
ocasorry-cc -O2 -c my_secret.c -o my_secret.o
```

### Compiler Options:
- `--ocasorry-disable`: Pass-through mode (no obfuscation)
- `--ocasorry-no-mba`: Disable MBA pass
- `--ocasorry-no-cff`: Disable Control Flow Flattening
- `--ocasorry-no-opaque`: Disable Opaque Predicates
- `--ocasorry-no-literals`: Disable String Encryption
- `--ocasorry-no-split`: Disable Variable Splitting
- `--ocasorry-implicit`: Enable Signal-driven Implicit Flow
- Environment variables: `OCASORRY_CC=gcc`, `OCASORRY_VERBOSE=1`

---

## 🚀 Getting Started

### Prerequisites
- **OCaml** >= 5.0.0
- **Dune** >= 3.10
- **Opam packages**: `goblint-cil`, `ppx_deriving`, `ppx_deriving_yojson`
- **C Compiler**: `clang` or `gcc`

Install dependencies via opam:
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

### Run Automated Test Suite (7 Suites)
```bash
dune runtest
```

---

## 📄 License

MIT License.
