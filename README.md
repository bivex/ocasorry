# OcaSorry

**OcaSorry** is an advanced, multi-target code obfuscator and native JIT execution engine written in **OCaml 5**, designed following **Domain-Driven Design (DDD)** and **Hexagonal Architecture (Ports & Adapters)**.

It combines **C Source-to-Source AST transformations** (powered by George Necula's [CIL / Goblint-CIL](https://github.com/cil-project/cil)) with a **native AArch64 (ARM64 / Apple Silicon) machine code JIT emitter** and an **ECMA-335 CIL bytecode VM**.

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
                       │            [ CLI Adapter | Test Suites ]               │
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

### 1. Mixed Boolean-Arithmetic (MBA)
Transforms standard arithmetic (`+`, `-`, `^`) into non-linear boolean identities:
- $x + y \iff (x \oplus y) + 2(x \land y)$
- $x + y \iff (x \lor y) + (x \land y)$
- $x + y \iff 2(x \lor y) - (x \oplus y)$
- $x - y \iff (x \oplus y) - 2(\sim x \land y)$
- $x \oplus y \iff (x \lor y) - (x \land y)$

### 2. Control Flow Flattening (CFF)
Flattens structured logic (loops, branches, sequential statements) into a state-machine switch dispatcher (`__cff_state`) with randomized case ordering.

### 3. Invariant Opaque Predicates
Injects mathematically invariant conditions:
- $(x \land \sim x) = 0$ (Always zero for any integer)
- Dead branches filled with invalid opcodes, deceptive instructions, or trap stubs that are never executed at runtime.

### 4. EncodeLiterals (String Encryption)
- Automatically intercepts all string literals `Const (CStr "...")`.
- Replaces strings with encrypted static byte arrays `static char __enc_lit_X[]` using generated keys.
- Inserts lazy inline decryptor guards into function prologues, leaving zero plain-text strings in binary `.rodata`.

### 5. Implicit Flow (Signal / Exception Driven Dispatch)
- Replaces explicit conditional branches `if (cond) { A } else { B }` with hardware signal traps.
- Sets a global handler for `SIGSEGV` and checkpoints execution via `sigsetjmp`.
- If condition is true, dereferences `NULL` (`*(volatile int*)0 = 42`), causing a signal trap that jumps directly to the target block via `siglongjmp`, breaking static decompiler CFGs and symbolic executors (angr, IDA, Ghidra).

### 6. Native AArch64 JIT Memory Engine
- Emits raw 32-bit ARM64 machine instructions (little-endian byte streams).
- Resolves PC-relative branch targets dynamically.
- Allocates executable memory via `mmap(MAP_JIT)` with full Apple Silicon W^X protection management (`pthread_jit_write_protect_np(0/1)`) and instruction cache flush (`sys_icache_invalidate`).

---

## 📂 Project Structure

```
ocasorry/
├── bin/
│   ├── dune
│   └── main.ml                      # Driving Adapter: CLI entry point and multi-target demo
│
├── lib/
│   ├── dune
│   ├── domain/                      # 1. Pure Domain Layer (Entities, VOs, Ports, Services)
│   │   ├── types.ml                 # Registers (X0..X30), Immediates, Conditions
│   │   ├── ast.ml                   # AArch64 Machine Instructions AST
│   │   ├── cfg.ml                   # BasicBlock and ControlFlowGraph aggregates
│   │   ├── cil_opcodes.ml           # ECMA-335 CIL Opcode definitions
│   │   ├── ports/                   # Driven Ports (SPI Interfaces)
│   │   │   ├── c_source_port.ml     # C Parsing & Emitter Port
│   │   │   ├── encoder_port.ml      # Binary Machine Code Encoder Port
│   │   │   ├── executor_port.ml     # JIT / Memory Execution Port
│   │   │   └── entropy_port.ml      # Randomness Source Port
│   │   └── services/                # Domain Transformation Services
│   │       ├── mba_service.ml       # Machine code MBA Rewriter
│   │       ├── opaque_predicate_service.ml # Machine code Invariants
│   │       ├── flattening_service.ml# Machine code Control Flow Flattening
│   │       ├── c_mba_service.ml     # CIL C-AST MBA Rewriter
│   │       ├── c_opaque_service.ml  # CIL C-AST Invariant Inserter
│   │       ├── c_flattening_service.ml # CIL C-AST Control Flow Flattening
│   │       ├── c_encode_literals_service.ml # CIL C-AST String Encryption
│   │       └── c_implicit_flow_service.ml   # CIL C-AST Signal-driven Dispatch
│   │
│   ├── application/                 # 2. Application Layer (Use Cases)
│   │   ├── obfuscation_pipeline.ml  # CFG pipeline configuration
│   │   ├── jit_runner_usecase.ml    # CFG -> Obfuscate -> Encode -> JIT Exec
│   │   └── obfuscate_c_source_usecase.ml # C Code -> Parse -> Obfuscate -> Emit
│   │
│   └── infrastructure/              # 3. Driven Adapters (Implementations)
│       ├── c_frontend/
│       │   └── goblint_cil_adapter.ml      # Goblint-CIL C parser/printer adapter
│       ├── encoders/
│       │   ├── aarch64_encoder_adapter.ml  # Native ARM64 binary emitter
│       │   └── cil_encoder_adapter.ml      # ECMA-335 CIL bytecode emitter
│       ├── runtime/
│       │   ├── mmap_stubs.c                # C-FFI: mmap(MAP_JIT) + cache flush
│       │   ├── posix_mmap_adapter.ml       # Native JIT executor adapter
│       │   └── cil_vm_adapter.ml           # Stack Machine VM executor adapter
│       └── random/
│           └── system_entropy_adapter.ml   # Cryptographic/System PRNG adapter
│
└── test/
    ├── dune
    └── test_arm_obfuscator.ml       # Comprehensive multi-target test suite (5 suites)
```

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

### Build the Project
```bash
dune build
```

### Run Multi-Target Demo
```bash
dune exec ./bin/main.exe
```

### Run Automated Test Suite
```bash
dune runtest
```

---

## 🧪 Example: Source-to-Source Transformation

### Original C Source
```c
extern int printf(const char *format, ...);

int compute(int x, int y) {
    if (x > y) {
        printf("Branch A: x is greater!\n");
    } else {
        printf("Branch B: y is greater or equal!\n");
    }
    int sum = x + y;
    int res = sum ^ 0x5A5A;
    return res;
}
```

### Obfuscated Output (`EncodeLiterals` + `ImplicitFlow` + `MBA` + `CFF`)
```c
#include <signal.h>
#include <setjmp.h>

static sigjmp_buf __implicit_jmp_buf;
static void __implicit_signal_handler(int sig) {
    signal(11, __implicit_signal_handler);
    siglongjmp(__implicit_jmp_buf, 1);
}

static char __enc_lit_1[25] = { 144, 160, 179, 188, ... };
static char __dec_lit_1[25];
static int  __init_lit_1 = 0;

int compute(int x, int y) {
  int sum, res, __idx_1, __idx_2, __implicit_dummy, __cff_state;
  int * volatile __implicit_ptr;
  int __implicit_jmp_res;

  __cff_state = 10;
  while (1) {
    if (__cff_state != 0) {
      switch (__cff_state) {
      case 124: 
        if (__implicit_jmp_res == 0) {
          __implicit_ptr = x > y ? (int *)0 : &__implicit_dummy;
          *__implicit_ptr = 117; // Triggers SIGSEGV if x > y
          printf((char const *)(&__dec_lit_2[0]));
        } else {
          printf((char const *)(&__dec_lit_1[0])); // Runs on caught signal
        }
        __cff_state = 130;
        break;
      case 130:
        sum = (x ^ y) + ((x & y) << 1);          // Linear MBA
        res = (sum | 0x5A5A) - (sum & 0x5A5A);   // Linear MBA
        __cff_state = 144;
        break;
      case 144:
        return res;
      /* ... remaining dispatcher states & lazy decryptor loops ... */
      }
    } else break;
  }
}
```

---

## 🗺️ Roadmap

- [x] DDD Hexagonal Architecture with Ports & Adapters
- [x] AArch64 (ARM64) Machine Code JIT Engine with W^X cache management
- [x] ECMA-335 CIL Bytecode Encoder & Stack Machine VM
- [x] George Necula CIL (`goblint-cil`) AST Integration
- [x] Mixed Boolean-Arithmetic (MBA) Rewriter
- [x] Control Flow Flattening (CFF) State Machine Dispatcher
- [x] Invariant Opaque Predicates
- [x] `EncodeLiterals` (String Literal Encryption & Lazy Decryptors)
- [x] `ImplicitFlow` (Signal / Hardware Exception-Driven Flow)
- [ ] **Virtualization Engine (`Virtualize`)**: Compile functions into custom randomized bytecode with an encrypted threaded-code interpreter.
- [ ] **Compiler Wrapper (`ocasorry-cc`)**: Drop-in `CC=ocasorry-cc` wrapper for building make/cmake C projects transparently.
- [ ] **Polynomial MBA & SMT-Hardening**: Deep polynomial MBA identities designed to defeat automated symbolic executors (Z3).
- [ ] **Anti-Debugging & Integrity Checks**: System debugger detection (`ptrace(PT_DENY_ATTACH)`, `sysctl`) and basic block self-checksumming.

---

## 📄 License

MIT License.
