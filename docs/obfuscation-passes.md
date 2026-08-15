# Obfuscation Techniques & Passes

This document details the transformation algorithms implemented in **Vectis**.

---

## 1. Relational Boundary & Comparison Morphing (`RelationalMorph`)
**Module**: `lib/domain/services/c_source/morphing/c_relational_morph_service.ml`

Transforms relational and equality comparisons into non-trivial bitwise/arithmetic formulas:
- Equality / Inequality: $(a == b) \iff ((a \oplus b) == 0)$, $(a \neq b) \iff ((a \oplus b) \neq 0)$
- Relational Ordering: $(a < b) \iff ((a - b) < 0) \mid !(a \ge b)$, $(a > b) \iff ((b - a) < 0) \mid !(a \le b)$
- Safe Division Guards: $(a / b) \iff (b == 0 \ ? \ 0 : a / b)$

---

## 2. C-Level Bytecode Virtualization (`random_vISA` Integration)
**Module**: `lib/domain/services/c_source/virtualization/c_random_visa_virtualize_service.ml`

Translates targeted function bodies into randomized 32-bit RISC-V Vector Instruction words (`.vbc` format with `0x57` opcodes) generated in static memory, replacing the function body with an embedded C11 / C99 VCPU interpreter with vector registers (`v0-v31`), scalar registers, and an execution loop.

---

## 3. Stateful Rolling Bytecode Key Chain
**Module**: `lib/domain/services/c_source/virtualization/c_rolling_vkey_service.ml`

Ties instruction decryption directly to execution history using an algebraic recurrence:
$$VKey_{n+1} = (VKey_n \times 33) \oplus (\text{DecryptedOp}_n + \text{0x9E3779B9})$$
Each instruction can only be decrypted if every preceding instruction was executed in valid order. Out-of-order execution, isolated emulation, or memory tampering causes immediate key divergence and VCPU fault.

---

## 4. Polymorphic VCPU Context & Struct Scrambling
**Module**: `lib/domain/services/c_source/virtualization/c_vcpu_context_scramble_service.ml`

Randomizes internal field order, register indices, and padding byte offsets in virtual processor context structures (`struct __vcpu_state`) for every compilation build, neutralizing generic de-virtualization scripts (IDAPython, Binary Ninja plugins).

---

## 5. In-Memory Ephemeral Payload Unpacking
**Module**: `lib/domain/services/c_source/loader/c_ephemeral_payload_service.ml`

Stores encrypted code and bytecode payloads in static memory, decrypts into temporary anonymous memory pages (`mmap`), executes the payload, and immediately overwrites memory with zeroes (`memset`) before deallocating (`munmap`), thwarting linear memory dumpers and signature scanners.

---

## 6. Dynamic POSIX API Hashing (`ImportHide`)
**Module**: `lib/domain/services/c_source/loader/c_api_hash_resolver_service.ml`

Conceals external standard library and system functions from Mach-O and ELF import tables (`nm`, `otool -L`, `readelf`) by replacing direct calls with dynamic `dlopen(0, RTLD_LAZY)` + `dlsym` resolution guided by compile-time CRC32 symbol hashes.

---

## 7. Pre-Main Security Constructor (`EarlyStager`)
**Module**: `lib/domain/services/c_source/loader/c_early_constructor_service.ml`

Injects `__attribute__((constructor(101)))` stagers that execute before `main()` during runtime loader (`dyld` / `ld-linux.so`) initialization, executing anti-debug checks, environment validation, and crypto state preparation before debuggers can catch entrypoint breakpoints.

---

## 8. Floating-Point Mixed Boolean-Arithmetic (`FloatMBA` FLOB Lifting)
**Module**: `lib/domain/services/c_source/data_encoding/c_float_mba_service.ml`

Lifts IEEE-754 floating-point operations (`float`, `double`) into a fixed-scale integer domain with binary expansions:
$$x_{\text{lifted}} = (\text{int64\_t})(x \cdot 2^k)$$
Applies bitwise Mixed Boolean-Arithmetic expansions over the lifted representations, and projects back to IEEE-754 space at computation output points, protecting deep neural networks and mathematical routines from decompiler analysis.

---

## 9. Basic Block Splitting (`BBSplit` Jitter Jumps)
**Module**: `lib/domain/services/c_source/control_flow/c_basic_block_split_service.ml`

Splits contiguous basic blocks and statement sequences into fragmented blocks connected by explicit labels and unconditional `goto` jumps:
```c
stmt_1;
goto __split_bb_1;
__split_bb_1:
stmt_2;
```
disrupting token sequence locality, basic-block embeddings, and LLM attention windows (defeating LLM-based malware detection and AST analyzers).

---

## 10. Decentralized Tree Dispatcher & Decoy Hubs (`DecentDisp` Anti-VMTag)
**Module**: `lib/domain/services/c_source/virtualization/c_decentralized_dispatcher_service.ml`

Deconstructs $N$-way centralized switch dispatchers into balanced binary if-else decision trees where every basic block has out-degree $D_{\text{out}} \le 2$. Injects an unreachable 32-way decoy hub guarded by an unsolvable Diophantine equation ($x^2 \equiv 2 \pmod 4$), deceiving topological de-virtualization passes (such as LLVM VMTag / arXiv:2601.12916) into analyzing bogus handlers.

---

## 11. Opcode Equalization & Histogram Smoothing (`OpcodeEqualize` Anti-DRLDO)
**Module**: `lib/domain/services/c_source/morphing/c_opcode_equalize_service.ml`

Injects balanced multi-class arithmetic, shift, bitwise, and logical instructions to flatten the opcode frequency histogram and maximize Shannon entropy across the binary, preventing Deep Reinforcement Learning agents (like DRLDO) from learning statistical pruning policies.

---

## 12. Dataflow-Entangled Anti-Slicing Computation (`AntiSlicing`)
**Module**: `lib/domain/services/c_source/morphing/c_anti_slicing_entanglement_service.ml`

Entangles phantom variables into live computation paths using algebraic invariants ($y = (x \oplus K) \cdot 2 - (x \oplus K) - (x \oplus K) \equiv 0$). Adds $y$ to active output variables to create hard Def-Use dependencies that static program slicers and dead-code eliminators cannot remove.

---

## 13. Instruction Substitution (`InstrSubst` with Opcode Normalization)
**Module**: `lib/domain/services/c_source/morphing/c_instruction_subst_service.ml`

Replaces basic arithmetic and bitwise expressions with a stochastic selection across orthogonal algebraic equivalence classes:
- $x + 1 \iff -\sim x \mid x - (-1)$
- $x - 1 \iff \sim -x \mid x + (-1)$
- $x \oplus y \iff (x \lor y) - (x \land y) \mid (x \land \sim y) \lor (\sim x \land y) \mid (x \lor y) \land \sim(x \land y)$
- $x + y \iff x - (-y) \mid (x \oplus y) + 2(x \land y) \mid (x \lor y) + (x \land y)$

---

## 14. Ghost Code Injection (`GhostCode` with Opcode Blending)
**Module**: `lib/domain/services/c_source/morphing/c_ghost_code_service.ml`

Injects diverse reversible instruction sequences modifying local variables with algebraic ring compensation ($\sum \Delta \equiv 0$):
- Compound ring: $v = ((v + K_1) \oplus K_2) \oplus K_2 - K_1$
- Bitwise inversion: $v = \sim(\sim v)$
- Linear scaling: $v = (v - K) + K$

---

## 15. Instruction Permutation (`InstrPermute` via Def-Use Scheduling)
**Module**: `lib/domain/services/c_source/morphing/c_instruction_permute_service.ml`

Constructs Def-Use dependency graphs for basic block statements and permutes independent instruction pairs without altering semantic invariants.

---

## 16. Algorithmic Paradigm Morphing (Loop $\to$ Tail-Recursion)
**Module**: `lib/domain/services/c_source/morphing/c_loop_to_recursion_service.ml`

Replaces iterative loop constructs with auxiliary tail-recursive call trees, destroying natural loop header basic blocks and backward CFG edges.

---

## 17. Diophantine Opaque Predicates
**Module**: `lib/domain/services/c_source/control_flow/c_diophantine_opaque_service.ml`

Injects dead code guarded by unsolvable Diophantine equations and algebraic invariants:
- $x^2 \equiv 2 \pmod 4$ (Always False)
- $x(x+1)(x+2) \equiv 0 \pmod 6$ (Always True)

---

## 18. Live Range Splitting (`LiveRangeSplit`)
**Module**: `lib/domain/services/c_source/morphing/c_live_range_split_service.ml`

Splits variable lifetimes into phased variables (`v_phase2`) connected by handover operations, breaking SSA liveness analysis in decompilers.

---

## 19. Constant Unfolding (`ConstUnfold`)
**Module**: `lib/domain/services/c_source/morphing/c_constant_unfold_service.ml`

Deconstructs static integer constants $C$ into non-trivial algebraic expansions ($C \iff (C \oplus K) \oplus K$).

---

## 20. Stack Memory Aliasing (`StackAliasing` with S-Box)
**Module**: `lib/domain/services/c_source/morphing/c_stack_aliasing_service.ml`

Embeds local scalar variables into a unified stack byte frame with S-Box addressing permutations, preventing linear stack layout analysis.

---

## 21. Nested Multi-Layer VM (2-Tier Packed VM)
**Module**: `lib/domain/services/c_source/virtualization/c_nested_vm_service.ml`

Embeds an encrypted master interpreter commanding an inner worker interpreter on-the-fly with rolling keys ($K_{n+1} = f(K_n)$), creating combinatorial path explosion in symbolic execution engines (angr, Triton).

---

## 22. Self-Modifying Bytecode VM
**Module**: `lib/domain/services/c_source/virtualization/c_self_modifying_vm_service.ml`

Stores bytecode in an encrypted state. In the fetch-decode-execute loop, instructions are decrypted in memory immediately before execution and dynamically re-encrypted with a mutated key after execution, rendering static memory dumps useless.

---

## 23. JIT Bytecode Machine Code Compilation (`Jitify`)
**Module**: `lib/domain/services/c_source/virtualization/c_jitify_service.ml`

Injects an embedded runtime native AArch64 / ARM64 machine code generator that allocates executable memory pages and translates virtualized bytecode directly into raw machine code at runtime.

---

## 24. Anti-Debug Injection
**Module**: `lib/domain/services/c_source/anti_analysis/c_anti_debug_service.ml`

Injects kernel-level process inspection checks (`sysctl(KERN_PROC_PID, P_TRACED)` / `ptrace PT_DENY_ATTACH`) inside basic blocks, detecting attached debuggers (GDB, LLDB, x64dbg) and terminating the session immediately.

---

## 25. Anti-Disassembly (Junk Byte Desync)
**Module**: `lib/domain/services/c_source/anti_analysis/c_anti_disassembly_service.ml`

Injects inline assembly directives with opcode bytes resembling valid multi-byte instruction prefixes inside opaque dead code blocks to desynchronize linear sweep and recursive disassemblers.

---

## 26. Self-Checksumming (Hash Guards)
**Module**: `lib/domain/services/c_source/anti_analysis/c_self_checksum_service.ml`

Calculates runtime CRC32 checksums of function memory pages to detect software breakpoints (`0xCC` / `BRK`) and active memory patching.

---

## 27. Timing Verification (Anti-Stepping)
**Module**: `lib/domain/services/c_source/anti_analysis/c_timing_check_service.ml`

Injects high-resolution monotonic timer delta checks (`mach_absolute_time()`) between basic blocks, detecting interactive debugger single-stepping.

---

## 28. Dynamic Hook Detection
**Module**: `lib/domain/services/c_source/anti_analysis/c_hook_detect_service.ml`

Verifies function pointers and memory prologue bytes to detect Frida, Substrate, or Mach-O symbol interposing.

---

## 29. Identifier Renaming & Symbol Hashing (`RenameSymbols`)
**Module**: `lib/domain/services/c_source/symbols/c_rename_symbols_service.ml`

Scrambles all non-exported local variables, static functions, and formal arguments into visually confusing homoglyph strings (e.g. `_l1I_lI1l_...`), eliminating meaningful identifiers for human analysts.

---

## 30. Source Directives Stripping (`StripDirectives`)
**Module**: `lib/domain/services/c_source/symbols/c_strip_directives_service.ml`

Strips `#line` pragmas and references to original development filepaths and directory structures from the emitted C source code.

---

## 31. Function Inlining (`Inline`)
**Module**: `lib/domain/services/c_source/inter_procedural/c_inline_service.ml`

Inlines small non-recursive functions directly into call sites across the AST, eliminating call-graph boundaries and increasing local analysis surface for subsequent intra-procedural passes.

---

## 32. Call Graph Flattening (Indirect Call Routing)
**Module**: `lib/domain/services/c_source/inter_procedural/c_call_graph_flatten_service.ml`

Replaces direct function calls `target_fn(a, b)` with indirect dispatch through a global function pointer table (`static void *__indirect_call_table[]`), concealing static call hierarchy from IDA Pro and Ghidra.

---

## 33. Cross-Function Bogus Call Injection
**Module**: `lib/domain/services/c_source/inter_procedural/c_bogus_calls_service.ml`

Injects dead calls between unrelated functions guarded by algebraic opaque predicates (`(x & ~x) != 0`), generating deceptive false edges in high-level architectural call graphs.

---

## 34. Arithmetic Exception Flow (`SIGFPE`)
**Module**: `lib/domain/services/c_source/implicit_flow/c_sigfpe_flow_service.ml`

Converts conditional branches into arithmetic fault conditions (`__fpe_denom == 0`) intercepted by `sigsetjmp` / `siglongjmp` and a static signal handler.

---

## 35. Illegal Opcode Flow (`SIGILL`)
**Module**: `lib/domain/services/c_source/implicit_flow/c_sigill_flow_service.ml`

Replaces jumps with illegal opcodes / traps caught by a `SIGILL` signal handler.

---

## 36. Multi-Threaded Race Implicit Flow
**Module**: `lib/domain/services/c_source/implicit_flow/c_threaded_implicit_flow_service.ml`

Transmits branch decisions across thread boundaries using POSIX threads (`pthread`), eliminating sequential control flow edges in intra-procedural decompilation.

---

## 37. Syscall Error Return Flow
**Module**: `lib/domain/services/c_source/implicit_flow/c_syscall_error_flow_service.ml`

Communicates boolean state via error return codes of intentionally failing system calls (e.g. `access("/__nonexistent_trap__", 0) < 0`), confusing kernel trace analyzers (strace, dtruss).

---

## 38. Lookup Table Arithmetic (LUT)
**Module**: `lib/domain/services/c_source/data_encoding/c_lut_arithmetic_service.ml`

Converts arithmetic and bitwise byte operations into static 256-element lookup tables (`static const unsigned char __lut_xor_K[256]`):
```c
/* x ^ 0x5A becomes: */
__lut_xor_5A_1[x & 0xFF];
```

---

## 39. Array Folding & Interleaving
**Module**: `lib/domain/services/c_source/data_encoding/c_array_interleave_service.ml`

Transforms array index lookups by wrapping indices into non-trivial scaled interleaved expressions (`((idx << 1) - idx)`), preventing linear dataflow and cache locality tracking.

---

## 40. Struct Field Permutation & Padding
**Module**: `lib/domain/services/c_source/data_encoding/c_struct_permute_service.ml`

Reorders fields in structure definitions (`CompInfo`) and injects random padding fields (`int __pad_field_1;`), destroying struct layout assumptions in Ghidra / IDA Pro.

---

## 41. Pointer Swizzling & Pointer Masking
**Module**: `lib/domain/services/c_source/data_encoding/c_pointer_masking_service.ml`

Applies reversible XOR masking layers to pointer addresses at dereference sites, confounding dynamic taint tracking and automated pointer analyzers.

---

## 42. Homomorphic Data Encoding
**Module**: `lib/domain/services/c_source/data_encoding/c_homomorphic_service.ml`

Encodes scalar values into $x_H = (a \cdot x + b) \bmod 2^{32}$. Arithmetic operations $(+, -, *)$ proceed directly in the encoded domain without intermediate decoding until output points.

---

## 43. Dynamic / Math-Property Opaque Predicates
**Module**: `lib/domain/services/c_source/control_flow/c_dynamic_opaque_service.ml`

Generates dynamic invariants based on integer arithmetic properties:
- $(x \cdot (x + 1)) \bmod 2 = 0$ (Always True for any integer $x$).
- $((x \ll 2) + 2) \bmod 2 = 0$ (Always True for any integer $x$).
- $(x \mid 1) \bmod 2 \neq 0$ (Always True for any integer $x$).

---

## 44. Bogus Control Flow (BCF Code Cloning & Mutation)
**Module**: `lib/domain/services/c_source/control_flow/c_bogus_control_flow_service.ml`

Clones legitimate basic blocks, alters numeric constants in the duplicate, and guards the paths behind a Dynamic Opaque Predicate.

---

## 45. Loop Unrolling & Jittering
**Module**: `lib/domain/services/c_source/control_flow/c_loop_unroll_service.ml`

Unrolls loop bodies by a factor of 2 while interleaving non-interfering jitter computations (`__loop_jitter = (__loop_jitter * 31) ^ 0x5A`).

---

## 46. Loop Fission & Segmentation
**Module**: `lib/domain/services/c_source/control_flow/c_loop_fission_service.ml`

Splits multi-statement loop bodies into sequenced execution phases (`__loop_phase`), breaking loop invariant analysis.

---

## 47. Indirect Jump Tables (Computed Dispatch)
**Module**: `lib/domain/services/c_source/control_flow/c_indirect_jump_service.ml`

Converts sequential statement blocks into an indirect indexed dispatch table (`switch(__indirect_state)`), breaking linear code layout.

---

## 48. Function Merging (`Merge`)
**Module**: `lib/domain/services/c_source/c_merge_functions_service.ml`

Merges pairs of independent C functions into a monolithic dispatcher function `__merged_fn(selector, ...)`.

---

## 49. Function Outlining (`Outline`)
**Module**: `lib/domain/services/c_source/c_outline_service.ml`

Slices contiguous statement blocks from function bodies into separate `static` helper functions passing local variables via pointer references.

---

## 50. High-Order Polynomial MBA & Invertible Affine Transformations (Anti-Z3)
**Module**: `lib/domain/services/c_source/c_polynomial_mba_service.ml`

Generates non-linear polynomial expressions coupled with **Invertible Affine Layers over $\mathbb{Z}_{2^{32}}$**:
$$E' = a^{-1} \cdot \Big( (a \cdot E + b) \Big) - (a^{-1} \cdot b) \pmod{2^{32}}$$
where $a^{-1} \pmod{2^{32}}$ is computed via Newton-Raphson modular inverse iteration.

---

## 51. Linear Mixed Boolean-Arithmetic (MBA)
**Modules**: `lib/domain/services/native/mba_service.ml`, `lib/domain/services/c_source/c_mba_service.ml`

Linear MBA replaces arithmetic operations with equivalent bitwise formulas ($x + y \iff (x \oplus y) + 2(x \land y)$).

---

## 52. Control Flow Flattening (CFF)
**Modules**: `lib/domain/services/native/flattening_service.ml`, `lib/domain/services/c_source/c_flattening_service.ml`

Transforms high-level structured control flow into a flat, single-loop state machine dispatcher (`while(1) switch(__cff_state)`).

---

## 53. Invariant Opaque Predicates
**Modules**: `lib/domain/services/native/opaque_predicate_service.ml`, `lib/domain/services/c_source/c_opaque_service.ml`

Injects dead code branches guarded by algebraic tautologies ($(x \land \sim x) \neq 0$).

---

## 54. EncodeLiterals (String Literal Encryption)
**Module**: `lib/domain/services/c_source/c_encode_literals_service.ml`

Encrypts string literals at compile-time into byte arrays with lazy in-function runtime decryptors.

---

## 55. Variable Splitting & Data Encoding (`EncodeData`)
**Module**: `lib/domain/services/c_source/c_encode_data_service.ml`

Splits local scalar integer variables $v$ into two distinct variables $(v_{s1}, v_{s2})$: $v = v_{s1} + v_{s2}$.

---

## 56. C-Level Implicit Flow (Signals: SIGSEGV)
**Module**: `lib/domain/services/c_source/c_implicit_flow_service.ml`

Replaces explicit conditional jumps with signal-driven control flow via `NULL` dereference and `sigsetjmp` / `siglongjmp`.
