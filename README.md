# OcaSorry

**OcaSorry** is an advanced, multi-target code obfuscator and multi-tier native JIT execution engine written in **OCaml 5**, designed following **Domain-Driven Design (DDD)** and **Hexagonal Architecture (Ports & Adapters)**.

It combines **C Source-to-Source AST transformations** (powered by George Necula's [CIL / Goblint-CIL](https://github.com/cil-project/cil)) with a **Two-Level JIT Engine**, a **drop-in compiler wrapper (`ocasorry-cc`)**, a **native AArch64 (ARM64 / Apple Silicon) machine code emitter**, and an **ECMA-335 CIL bytecode VM**.

---

## 🎯 Why OCaml + CIL Instead of LLVM?

While LLVM is standard for general-purpose compilation, it has fundamental drawbacks when building high-resilience obfuscators:

| Problem with LLVM | Advantage of OCaml + CIL (`OcaSorry`) |
| :--- | :--- |
| **Normalizing IR**: LLVM IR constantly canonicalizes control flow, unfolds opaque predicates, and removes dead code. | **AST Preservation**: CIL AST preserves intentional entropy, dead branches, and complex structures without optimization passes un-obfuscating them. |
| **Heavy Dependency**: LLVM requires massive toolchains (hundreds of MBs/GBs). | **Lightweight & Fast**: Pure OCaml with algebraic data types, pattern matching, and minimal runtime footprint. |
| **Hardware Tricks**: Difficult to execute signal traps, self-modifying code, and custom inline dispatchers. | **Full Low-Level Control**: Native support for signal handlers (`SIGSEGV`/`SIGTRAP`/`sigsetjmp`), custom `mmap(MAP_JIT)` execution, and raw byte-level assembly synthesis. |

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
│  • Two_tier_jit_usecase        (Two-Level Metamorphic JIT + Signal Router)                              │
│                                                                                                         │
│  ┌───────────────────────────────────────────────────────────────────────────────────────────────────┐  │
│  │ DOMAIN CORE (Pure, Zero-Dependency Business Logic)                                                │  │
│  │                                                                                                   │  │
│  │  [ Value Objects & Entities ]                                                                     │  │
│  │    • Reg (X0..X30, SP), Imm, Condition, Label, Instruction AST, BasicBlock, CFG                  │  │
│  │                                                                                                   │  │
│  │  [ Native IR Services ]                 [ CIL C-AST Services ]                                    │  │
│  │    • Mba_service                          • C_mba_service (MBA)                                   │  │
│  │    • Flattening_service                   • C_flattening_service (CFF)                            │  │
│  │    • Opaque_predicate_service             • C_opaque_service (Opaque Predicates)                  │  │
│  │    • Two_tier_jit_service                 • C_encode_literals_service (String Encryption)         │  │
│  │                                           • C_encode_data_service (Variable Splitting)            │  │
│  │                                           • C_implicit_flow_service (Signal Control Flow)         │  │
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

## ⚡ Supported Obfuscation & JIT Pipelines

### 1. Two-Level JITting + Hardware Implicit Flow (`Target 4`)
- **Tier 1 (Outer JIT Stager)**: A compact native AArch64 JIT payload that triggers a hardware trap (`BRK #0x42` / `SIGTRAP`).
- **Tier 2 (Inner Encrypted Payload)**: The actual protected algorithm (obfuscated with MBA + Control Flow Flattening), encrypted with dynamic session keys in memory.
- **Hardware Fault Redirection**: When Tier 1 runs, the kernel signal handler catches the fault, decrypts Tier 2 into executable memory, modifies the hardware program counter register (`ucontext->__ss.__pc = tier2_entry`), and resumes execution directly into Tier 2 without any call/branch instructions in the binary!

### 2. Variable Splitting & Data Encoding (`EncodeData`)
- Splits scalar integer variables $v$ into two distinct components $(v_{s1}, v_{s2})$ maintaining $v = v_{s1} + v_{s2}$.
- Decomposes write operations into bitwise shifts and differences.

### 3. Mixed Boolean-Arithmetic (MBA)
Transforms arithmetic (`+`, `-`, `^`) into non-linear boolean identities ($x + y \iff (x \oplus y) + 2(x \land y)$).

### 4. Control Flow Flattening (CFF)
Flattens functions into a randomized state-machine switch dispatcher (`__cff_state`).

### 5. Invariant Opaque Predicates
Injects mathematically invariant dead branches ($(x \land \sim x) = 0$) filled with invalid opcodes or trap stubs.

### 6. EncodeLiterals (String Encryption)
Encrypts static strings into byte arrays with lazy in-function decryptors, leaving zero plain-text strings in `.rodata`.

### 7. C-Level Implicit Flow (Signals)
Replaces `if/else` branching with `NULL` dereferencing caught by `SIGSEGV` and routed via `sigsetjmp` / `siglongjmp`.

---

## 🚀 Quick Start

### Build Everything
```bash
dune build
```

### Run Multi-Target Demo (Including Two-Tier JIT)
```bash
dune exec ./bin/main.exe
```

### Run 8 Automated Test Suites
```bash
dune runtest
```

---

## 📄 License

MIT License.
