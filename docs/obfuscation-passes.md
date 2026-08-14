# Obfuscation Techniques & Passes

This document details the transformation algorithms implemented in **OcaSorry**.

---

## 1. Function Merging (`Merge`)
**Module**: `lib/domain/services/c_source/c_merge_functions_service.ml`

Merges pairs of independent, unrelated C functions (e.g. `calculate_area` and `calculate_perimeter`) into a single monolithic dispatcher function:
```c
static int __merged_fn_a_fn_b(int __selector, int a0, int a1, int a2, int a3) {
    if (__selector == 0x3F1A) {
        /* Body of Function A */
    } else if (__selector == 0x9B4C) {
        /* Body of Function B */
    } else {
        return 0;
    }
}
```
- Original function definitions are replaced with lightweight proxy stubs passing the secret selector.
- When combined with **Control Flow Flattening**, the basic blocks of both functions are completely intermingled in a single unified state-machine switch loop.

---

## 2. Function Outlining (`Outline`)
**Module**: `lib/domain/services/c_source/c_outline_service.ml`

Slices contiguous statement blocks from function bodies into separate `static` helper functions:
```c
static void __outlined_fn_1(int *x_ptr, int *step_ptr) {
    *step_ptr = (*x_ptr * 3) + 50;
}
```
- Local variables are passed via pointer references (`&x`, `&step`).
- Fragments intra-procedural dataflow graphs and confuses static analysis heuristics in IDA Pro and Ghidra.

---

## 3. High-Order Polynomial MBA & Invertible Affine Transformations (Anti-Z3)
**Module**: `lib/domain/services/c_source/c_polynomial_mba_service.ml`

Generates non-linear polynomial expressions coupled with **Invertible Affine Layers over the ring $\mathbb{Z}_{2^{32}}$**, causing combinatorial state-space explosion in symbolic execution solvers:
$$E' = a^{-1} \cdot \Big( (a \cdot E + b) - b \Big) \pmod{2^{32}}$$
where $a^{-1} \pmod{2^{32}}$ is computed via Newton-Raphson modular inverse iteration.

---

## 4. Linear Mixed Boolean-Arithmetic (MBA)
**Modules**: `lib/domain/services/native/mba_service.ml`, `lib/domain/services/c_source/c_mba_service.ml`

Linear MBA replaces arithmetic operations with equivalent bitwise formulas:
- $x + y \iff (x \oplus y) + 2(x \land y)$
- $x + y \iff (x \lor y) + (x \land y)$
- $x + y \iff 2(x \lor y) - (x \oplus y)$
- $x - y \iff (x \oplus y) - 2(\sim x \land y)$
- $x \oplus y \iff (x \lor y) - (x \land y)$

---

## 5. Control Flow Flattening (CFF)
**Modules**: `lib/domain/services/native/flattening_service.ml`, `lib/domain/services/c_source/c_flattening_service.ml`

Transforms high-level structured control flow (nested `if`, `while`, `for`) into a flat, single-loop state machine dispatcher:
1. Basic blocks are assigned pseudo-random state IDs.
2. The function body is placed inside a `while(1) switch(__cff_state)` construct.
3. Execution order is shuffled randomly in the AST, completely destroying the visual graph hierarchy in decompilers (IDA, Ghidra).

---

## 6. Invariant Opaque Predicates
**Modules**: `lib/domain/services/native/opaque_predicate_service.ml`, `lib/domain/services/c_source/c_opaque_service.ml`

Injects dead code branches guarded by algebraic tautologies:
- Condition: $(x \land \sim x) \neq 0$ (Guaranteed `false` for any signed or unsigned integer).
- The `true` branch is populated with junk code, deceptive instruction sequences, or invalid opcodes that confuse static disassemblers without ever executing.

---

## 7. EncodeLiterals (String Literal Encryption)
**Module**: `lib/domain/services/c_source/c_encode_literals_service.ml`

- Detects string constants in C AST (`Const (CStr "...")`).
- Encrypts each character at compile-time with a generated key: $E[i] = S[i] \oplus K$.
- Replaces string constants with pointers to static byte arrays: `static char __enc_lit_X[]`.
- Injects a lazy runtime decryptor guard in the function prologue, stripping open-text strings completely from the executable `.rodata` section.

---

## 8. Variable Splitting & Data Encoding (`EncodeData`)
**Module**: `lib/domain/services/c_source/c_encode_data_service.ml`

Splits local scalar integer variables $v$ into two distinct variables $(v_{s1}, v_{s2})$:
- Invariant maintained at all times: $v = v_{s1} + v_{s2}$.
- Assignment $v = \text{expr}$ is rewritten as:
  $$\text{temp} = \text{expr}, \quad v_{s2} = \text{temp} \gg 1, \quad v_{s1} = \text{temp} - (\text{temp} \gg 1)$$
- Every read access to $v$ becomes $(v_{s1} + v_{s2})$.

---

## 9. C-Level Implicit Flow (Signals)
**Module**: `lib/domain/services/c_source/c_implicit_flow_service.ml`

Replaces explicit conditional jumps with signal-driven control flow:
```c
volatile int *__implicit_ptr = (cond) ? (int*)0 : &__implicit_dummy;
signal(11, &__implicit_signal_handler);
if (sigsetjmp(__implicit_jmp_buf, 1) == 0) {
    *__implicit_ptr = 42; // Triggers SIGSEGV if cond == true
    else_branch();        // Runs if cond == false (valid pointer)
} else {
    then_branch();        // Runs after signal handler longjmp!
}
```
