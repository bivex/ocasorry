# Two-Level JITting & Hardware-Level Implicit Flow

This document describes the design and operation of the **Multi-Tier JIT Execution Engine** and **Hardware Signal Redirection** on Apple Silicon (AArch64).

---

## 🎯 Concept Overview

Traditional binary analysis tools (IDA Pro, Ghidra, angr) expect function calls to follow standard calling conventions (`BL`, `BLR`, `CALL`). 

**Two-Level JITting with Hardware Implicit Flow** breaks this model by:
1. Generating a metamorphic outer stager (**Tier 1**) that contains no references to the target function.
2. Encrypting the target machine code payload (**Tier 2**) in memory with an ephemeral session key.
3. Intentionally executing a hardware breakpoint trap (`BRK #0x42` / `SIGTRAP`) inside Tier 1.
4. Catching the hardware fault via a POSIX signal handler with `SA_SIGINFO`.
5. Modifying the CPU execution context (`ucontext_t->__ss.__pc`) to point directly to Tier 2 and resuming hardware execution.

---

## 🔄 Execution Workflow

```
                        Input Arguments: (x0, x1)
                                   │
                                   ▼
         ┌────────────────────────────────────────────────────────┐
         │              LEVEL 1: OUTER JIT STAGER                 │
         │  • Ultra-compact native AArch64 stager (8 bytes)       │
         │  • Instruction: BRK #0x42 (0xD4200840)                 │
         └─────────────────────────┬──────────────────────────────┘
                                   │
                   Hardware Fault  │ (SIGTRAP / SIGBUS)
                                   ▼
         ┌────────────────────────────────────────────────────────┐
         │     IMPLICIT SIGNAL FLOW ROUTER (ucontext_t)           │
         │  1. Signal handler catches fault from kernel           │
         │  2. Decrypts Tier 2 payload in memory on the fly       │
         │  3. Invalidates instruction cache                      │
         │     sys_icache_invalidate(tier2_mem, len)             │
         │  4. Overwrites hardware Program Counter register:      │
         │     uc->uc_mcontext->__ss.__pc = (uint64_t)tier2_mem;  │
         │  5. Returns from signal handler                        │
         └─────────────────────────┬──────────────────────────────┘
                                   │
               CPU resumes at PC   │ ZERO visible BL/BLR/B instructions!
                                   ▼
         ┌────────────────────────────────────────────────────────┐
         │              LEVEL 2: INNER JIT PAYLOAD                │
         │  • Target computation algorithm                        │
         │  • Full protection: MBA + CFF + Opaque Predicates      │
         │  • Computes result and returns value in x0             │
         └────────────────────────────────────────────────────────┘
```

---

## 🛡️ Apple Silicon W^X Compliance

On macOS (Apple Silicon ARM64), memory pages cannot be simultaneously writable and executable due to hardware Write-XOR-Execute (W^X) security enforcement.

**Vectis** manages this runtime protocol via:
1. `mmap(NULL, size, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_ANON | MAP_PRIVATE | MAP_JIT, -1, 0)`: Allocates JIT-capable virtual memory.
2. `pthread_jit_write_protect_np(0)`: Unprotects page for dynamic writing / XOR decrypting.
3. `pthread_jit_write_protect_np(1)`: Enables execution mode.
4. `sys_icache_invalidate(mem, len)`: Synchronizes instruction cache with modified data memory.
5. On Linux AArch64: `__builtin___clear_cache((char*)mem, (char*)mem + len)` is used instead.

---

## ⚡ 4. Native AArch64 Machine Code Compiler (`C_arm64_jit_compiler`)

Rather than relying on static pre-assembled byte sequences, Tier 4 features a **full native AArch64 JIT compiler** written in OCaml that translates Goblint-CIL function ASTs directly into 32-bit AArch64 machine instructions:

### Supported Instructions & Expressions:
* **Arithmetic**: `add` (`0x0B000000`), `sub` (`0x4B000000`), `mul` (`0x1B007C00`), `neg` (`0x4B0003E0`).
* **Bitwise Logic**: `and` (`0x0A000000`), `orr` (`0x2A000000`), `eor` (`0x4A000000`), `mvn` (`0x2A2003E0`).
* **Shifts**: `lsl` (`0x53000000` via UBFM), `lsr` (`0x53000000` via UBFM).
* **Comparisons & Conditional Sets**: `cmp` (`0x6B00001F`) + `cset` (`0x1A9F07E0` with inverted condition codes).
* **Branching**: `b.cond` (`0x54000000`) and unconditional `b` (`0x14000000`).
* **Immediate Loading**: `movz` (`0x52800000`) and `movk` (`0x72A00000`) for 32-bit constants.
* **Return**: `ret` (`0xD65F03C0`).

### Callee Register Preservation & Disjoint Scratches:
* **Prologue Parameter Preservation**: Formals `w0..w3` are moved to callee-preserved registers `w4..w7` during the prologue, ensuring that subexpression evaluations never overwrite incoming function arguments.
* **Disjoint Scratch Pools**: Expression evaluations use `w12..w15`, while local variables map to `w8..w11`.

---

## 🎲 5. Symbolic Label Resolution & Polymorphic Decoys

The compiler uses a 3-phase intermediate representation (`jit_item`: `Raw`, `Label`, `B_Cond`, `B_Uncond`):

1. **AST Lowering**: Emits basic blocks with symbolic labels.
2. **Polymorphic Decoy Insertion**: Injects non-destructive decoy instructions (`enc_eor wzr wzr wzr`, `enc_mov_reg wzr wzr`, `enc_nop`) with 20% probability. Because decoys use `WZR` (Zero Register) and `NOP`, no general-purpose registers (`w0..w15`) or stack pointers are corrupted.
3. **Word-Position Offset Resolution**: Computes exact relative instruction distances **after** all decoys are inserted, ensuring that PC-relative branches (`b.eq`, `b.ne`, `b.ge`, `b.lt`) never misalign.

---

## 🧹 6. 3-Pass DoD 5220.22-M Memory Sanitization

To ensure forensic-level confidentiality against RAM dumps, core dump analysis, and Frida memory scanning:

```c
static void __vectis_free_ephemeral_page(void *ptr, size_t sz) {
    if (ptr && ptr != MAP_FAILED) {
#if defined(__APPLE__) && (defined(__aarch64__) || defined(__arm64__))
        pthread_jit_write_protect_np(0); /* Switch to write mode before wiping */
#endif
        /* 3-Pass Secure DoD Sanitization */
        memset(ptr, 0x55, sz);  /* Pass 1: 01010101 pattern */
        memset(ptr, 0xAA, sz);  /* Pass 2: 10101010 pattern */
        memset(ptr, 0x00, sz);  /* Pass 3: Zero fill        */
        munmap(ptr, sz);
    }
}
```

---

## 🔗 7. Chained Multi-Stage JIT Pipelines & High-Frequency Loops

Vectis supports **compositional JIT chaining** across arbitrarily complex execution pipelines:

* **Pipeline Chains**: Multiple functions (`stage1_hash` $\to$ `stage2_branch` $\to$ `stage3_affine` $\to$ `stage4_finalize`) each maintain independent `.rodata` encrypted payloads and unique dynamic session keys. At any given microsecond, only the active stage resides in RAM.
* **High-Frequency Loops**: Successfully validated for 5,000+ continuous chained invocations with zero memory leaks and deterministic state preservation.
