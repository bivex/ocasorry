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

**Vectis** manages this in `mmap_stubs.c` via:
1. `mmap(NULL, size, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_ANON | MAP_PRIVATE | MAP_JIT, -1, 0)`
2. `pthread_jit_write_protect_np(0)`: Unprotect page for writing/decrypting code.
3. `pthread_jit_write_protect_np(1)`: Enable execution protection.
4. `sys_icache_invalidate(mem, len)`: Synchronizes instruction cache with modified data memory.
