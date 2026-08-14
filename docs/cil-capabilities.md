# George Necula's CIL / Goblint-CIL: Obfuscation Capabilities & Techniques

This document provides a comprehensive roadmap and technical index of all obfuscation, anti-analysis, and code-hardening techniques engineered on top of **George Necula's C Intermediate Language (CIL / Goblint-CIL)** Abstract Syntax Tree.

---

## 📊 Feature Status Matrix

- `[x]` = **Implemented & Verified in OcaSorry**
- `[ ]` = **Native Binary Protector & Loader Architecture (Next-Gen Roadmap)**

---

## 1. 🌀 Virtualization & Custom Interpreters

| Status | Technique | CIL AST Mechanism | Resilience Target |
| :---: | :--- | :--- | :--- |
| `[x]` | **C-Level Bytecode Virtualization (`Virtualize`)** | Integrates with `random_vISA` vector ISA synthesizer, encoding function logic into 32-bit RISC-V Vector Bytecode (`.vbc`) with an embedded C11 VCPU execution loop. | Disassemblers (IDA, Ghidra), Decompilers |
| `[x]` | **Nested Multi-Layer VM** | Embeds an interpreter inside another interpreter (Outer VM $\to$ Inner VM) with multi-tier dispatch tables. | Symbolic Execution (angr) |
| `[x]` | **Self-Modifying Bytecode** | Virtual machine dynamically rewrites its own bytecode in memory during execution via rolling XOR multi-phase keys. | Static Signatures & Memory Dumps |
| `[x]` | **JIT Bytecode Compilation (`Jitify`)** | Injects an embedded runtime AArch64 machine code generator that translates virtualized bytecode directly to executable RAM. | Static Reverse Engineering |
| `[x]` | **Stateful Rolling Bytecode Key Chain** | Ties instruction decryption to execution history ($VKey_{n+1} = f(VKey_n, Op_n)$); desynchronizes on out-of-order execution, isolated emulation, or memory tampering. | Memory Dumps, Isolated Emulators, SMT Solvers |

---

## 2. 🔀 Control-Flow Obfuscation

| Status | Technique | CIL AST Mechanism | Resilience Target |
| :---: | :--- | :--- | :--- |
| `[x]` | **Control Flow Flattening (`Flatten`)** | Collapses all structured basic blocks (`bstmts`) into a single-loop state machine (`while(1) switch(__cff_state)`). | Control Flow Graph (CFG) Analysis |
| `[x]` | **Invariant Opaque Predicates** | Injects algebraic tautologies (`(x & ~x) != 0`) guarding junk / trap code. | Static Disassemblers |
| `[x]` | **Dynamic / Math-Property Opaque Predicates** | Generates dynamic invariants based on integer arithmetic properties (`(x*(x+1)) % 2 == 0`, `((x<<2)+2) % 2 == 0`). | SMT / SAT Solvers (Z3) |
| `[x]` | **Bogus Control Flow (BCF Code Cloning)** | Clones real basic blocks, alters constants slightly, and guards fake copies with dynamic opaque predicates. | Pattern Matchers, Decompilers |
| `[x]` | **Loop Unrolling & Jittering** | Duplicates loop bodies (`Loop`) by a factor of 2 and inserts randomized non-interfering jitter computations. | Loop Invariant Analyzers |
| `[x]` | **Loop Fission & Segmentation** | Splits multi-statement loop bodies into sequenced segmented loop execution phases. | Loop Vectorizers / Analyzers |
| `[x]` | **Indirect Jump Tables (Computed Dispatch)** | Converts structured sequential blocks into an indirect indexed dispatch table. | CFG Reconstruction Engines |

---

## 3. 🔢 Data Obfuscation & Mathematical Transformations

| Status | Technique | CIL AST Mechanism | Resilience Target |
| :---: | :--- | :--- | :--- |
| `[x]` | **Linear Mixed Boolean-Arithmetic (MBA)** | Rewrites arithmetic (`+`, `-`, `^`) into 1st-order bitwise polynomial identities ($x + y \iff (x \oplus y) + 2(x \land y)$). | Human Reversers, Disassemblers |
| `[x]` | **High-Order Polynomial MBA (Anti-Z3)** | Injects non-linear polynomial expressions over $\mathbb{Z}_{2^{32}}$ and Invertible Affine Layers ($E' = a^{-1}(aE + b) - (a^{-1}b)$). | SMT / Symbolic Solvers (Z3, Triton) |
| `[x]` | **EncodeLiterals (String Encryption)** | Replaces static string literals with encrypted byte arrays and inserts lazy constructor / prologue decryptors. | Strings Analyzers (`strings`, Binwalk) |
| `[x]` | **Variable Splitting (`EncodeData`)** | Splits scalar local variables $v$ into $(v_{s1}, v_{s2})$ maintaining $v = v_{s1} + v_{s2}$ on all reads and writes. | Memory Scanners (Cheat Engine) |
| `[x]` | **Lookup Table Arithmetic (LUT)** | Converts arithmetic operations into 256-byte precomputed tables stored in `static` memory. | Algebraic Deobfuscators |
| `[x]` | **Array Folding & Interleaving** | Merges multiple array index accesses into scaled interleaved strides. | Dataflow Analysis |
| `[x]` | **Struct Field Permutation & Padding** | Reorders fields in `CompInfo` structs, injects random padding bytes, and scrambles field layout. | Struct Layout Recovery |
| `[x]` | **Pointer Swizzling / Pointer Masking** | Stores raw pointers XOR-masked with a secret key (`uintptr_t`), unmasking them at dereference sites (`*(int*)(p ^ MASK)`). | Pointer Analysis / Taint Tracking |
| `[x]` | **Homomorphic Data Encoding** | Rewrites scalar values into $(a \cdot x + b) \bmod m$ and lifts all arithmetic operators into the transformed domain. | Dynamic Binary Instrumentation (DBI) |

---

## 4. ⚡ Implicit Flow & Hardware Traps

| Status | Technique | CIL AST Mechanism | Resilience Target |
| :---: | :--- | :--- | :--- |
| `[x]` | **Signal-Driven Implicit Flow (`SIGSEGV`)** | Converts conditional jumps into `NULL` pointer writes intercepted by `sigsetjmp` / `siglongjmp`. | Symbolic Execution (angr, KLEE) |
| `[x]` | **Hardware CPU Register Redirection** | Modifies `ucontext_t->__ss.__pc` in signal handler to jump directly to decrypted JIT pages without branch instructions. | Native Debuggers & Disassemblers |
| `[x]` | **Arithmetic Exception Flow (`SIGFPE`)** | Routes branches through division-by-zero / arithmetic traps intercepted by `sigsetjmp` / `siglongjmp`. | Static Control Flow Analyzers |
| `[x]` | **Illegal Opcode Flow (`SIGILL`)** | Replaces jumps with `__builtin_trap()` / invalid machine opcodes caught by signal handlers. | Decompiler Call-Graph Builders |
| `[x]` | **Multi-Threaded Race Implicit Flow** | Transmits branch decisions across thread boundaries using `pthread_mutex_t` and `pthread_cond_wait`. | Concurrency Trackers |
| `[x]` | **Syscall Error Return Flow** | Communicates boolean state via error return codes of intentionally failing system calls. | Kernel Trace Analyzers |

---

## 5. 🧱 Inter-Procedural & Architectural Transformations

| Status | Technique | CIL AST Mechanism | Resilience Target |
| :---: | :--- | :--- | :--- |
| `[x]` | **Function Merging (`Merge`)** | Unifies two or more independent functions into a single monolithic function `__merged(selector, ...)`. | Function Boundary Detection |
| `[x]` | **Function Outlining (`Outline`)** | Slices statement sequences from function bodies into separate `static` subroutines passing pointers. | Intra-Procedural Dataflow Analyzers |
| `[x]` | **Function Inlining (`Inline`)** | Automatically inlines non-recursive functions across the AST using expression substitution. | Call Graph Reconstructors |
| `[x]` | **Call Graph Flattening (Indirect Call Routing)** | Replaces direct calls `foo(a, b)` with function pointer dispatch tables indexed by runtime hashes. | Inter-Procedural Call Analysis |
| `[x]` | **Cross-Function Bogus Call Injection** | Injects dead calls between unrelated functions to introduce false edges in IDA/Ghidra call graphs. | High-Level Architecture Analyzers |

---

## 6. 🛡️ Anti-Analysis, Anti-Debugging & Integrity

| Status | Technique | CIL AST Mechanism | Resilience Target |
| :---: | :--- | :--- | :--- |
| `[x]` | **Anti-Debug Injection** | Injects inline checks (`sysctl(KERN_PROC_PID, P_TRACED)` / `ptrace PT_DENY_ATTACH`) inside function basic blocks. | Dynamic Debuggers (GDB, LLDB, x64dbg) |
| `[x]` | **Anti-Disassembly (Junk Byte Desync)** | Injects `__asm__ volatile ("...")` with byte patterns resembling instructions immediately inside dead opaque blocks. | Linear Sweep & Recursive Disassemblers |
| `[x]` | **Self-Checksumming (Hash Guards)** | Calculates CRC32 of function memory pages at runtime; corrupts execution state if breakpoints (`0xCC` / `BRK`) exist. | Memory Patchers & Breakpoints |
| `[x]` | **Timing Verification (Anti-Stepping)** | Injects `mach_absolute_time()` delta checks between basic blocks to detect debugger single-stepping. | Interactive Reverse Engineers |
| `[x]` | **Dynamic Hook Detection** | Verifies integrity of function pointers and code prologue bytes to detect Frida, Substrate, or Mach-O interposing. | Dynamic Instrumentation Tools |

---

## 7. 🏷️ Symbol & Metadata Stripping

| Status | Technique | CIL AST Mechanism | Resilience Target |
| :---: | :--- | :--- | :--- |
| `[x]` | **Identifier Renaming / Symbol Hashing** | Renames all non-exported `varinfo.vname` to unreadable homoglyph strings (e.g. `_l1I_lI1l_...`) and entropy-derived identifiers. | Human Comprehension |
| `[x]` | **Source Directives Stripping** | Removes `#line` comments and original filename references from pretty-printed C output. | Source Mapping / Debugging Info |

---

## 8. 🏰 Native Binary Protector & Loader Architecture (POSIX / Mach-O / ELF)

| Status | Technique | CIL AST Mechanism | Resilience Target |
| :---: | :--- | :--- | :--- |
| `[x]` | **Dynamic POSIX API Hashing (`ImportHide`)** | Replaces external library calls (`sysctl`, `ptrace`, `socket`, `open`, `printf`) with dynamic `dlopen`/`dlsym` resolution by CRC32 hashes. | Import Tables (`nm`, `otool -L`, `readelf`) |
| `[x]` | **Pre-Main Security Constructor (`EarlyStager`)** | Injects `__attribute__((constructor(101)))` handlers that execute integrity hashing, VCPU preparation, and anti-debug before `main()`. | Entrypoint Breakpoints (`b main`), Early Attach |
| `[x]` | **Stateful Rolling Bytecode Key Chain** | Ties instruction decryption to execution history ($VKey_{n+1} = f(VKey_n, Op_n)$); desynchronizes on out-of-order execution or tampering. | Memory Dumps, Isolated Emulators, SMT Solvers |
| `[ ]` | **Polymorphic VCPU Context & Struct Scrambling** | Randomizes internal field ordering and offsets in virtual processor context structures (`struct __vcpu_state`) per compilation. | Universal De-Virtualization Plugins (IDAPython) |
| `[ ]` | **In-Memory Ephemeral Payload Unpacking** | Encrypts bytecode/code payloads in static memory, unpacking into executable RAM via `mmap` and zeroing memory immediately after. | Static Scanners, Linear RAM Dumpers |
