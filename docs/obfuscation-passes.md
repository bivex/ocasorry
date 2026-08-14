# Obfuscation Techniques & Passes

This document details the transformation algorithms implemented in **OcaSorry**.

---

## 1. Dynamic / Math-Property Opaque Predicates
**Module**: `lib/domain/services/c_source/control_flow/c_dynamic_opaque_service.ml`

Unlike static tautologies, dynamic opaque predicates synthesize algebraic relations based on integer properties:
- $(x \cdot (x + 1)) \bmod 2 = 0$ (Always True for any integer $x$).
- $((x \ll 2) + 2) \bmod 2 = 0$ (Always True for any integer $x$).
- $(x \mid 1) \bmod 2 \neq 0$ (Always True for any integer $x$).

---

## 2. Bogus Control Flow (BCF Code Cloning & Mutation)
**Module**: `lib/domain/services/c_source/control_flow/c_bogus_control_flow_service.ml`

Clones legitimate basic blocks, alters numeric constants and operations in the duplicate, and guards the paths behind a Dynamic Opaque Predicate:
```c
if (((x * (x + 1)) % 2) == 0) {
    /* Real basic block */
    result = (a + 10) ^ (b * 5);
} else {
    /* Mutated bogus basic block */
    result = (a + 83) ^ (b * 12);
}
```
Decompilers are forced to analyze two plausible control-flow branches, masking the true algorithm.

---

## 3. Loop Unrolling & Jittering
**Module**: `lib/domain/services/c_source/control_flow/c_loop_unroll_service.ml`

Unrolls loop bodies by a factor of 2 while interleaving non-interfering jitter computations (`__loop_jitter = (__loop_jitter * 31) ^ 0x5A`) between iterations to destroy loop symmetry.

---

## 4. Loop Fission & Segmentation
**Module**: `lib/domain/services/c_source/control_flow/c_loop_fission_service.ml`

Splits multi-statement loop bodies into sequenced execution phases (`__loop_phase`), breaking loop invariant analysis in automated deobfuscators.

---

## 5. Indirect Jump Tables (Computed Dispatch)
**Module**: `lib/domain/services/c_source/control_flow/c_indirect_jump_service.ml`

Converts sequential statement blocks into an indirect indexed dispatch table (`switch(__indirect_state)`), breaking linear code layout.

---

## 6. Function Merging (`Merge`)
**Module**: `lib/domain/services/c_source/c_merge_functions_service.ml`

Merges pairs of independent, unrelated C functions (e.g. `calculate_area` and `calculate_perimeter`) into a single monolithic dispatcher function `__merged_fn(selector, ...)`.

---

## 7. Function Outlining (`Outline`)
**Module**: `lib/domain/services/c_source/c_outline_service.ml`

Slices contiguous statement blocks from function bodies into separate `static` helper functions passing local variables via pointer references (`&x`, `&step`).

---

## 8. High-Order Polynomial MBA & Invertible Affine Transformations (Anti-Z3)
**Module**: `lib/domain/services/c_source/c_polynomial_mba_service.ml`

Generates non-linear polynomial expressions coupled with **Invertible Affine Layers over the ring $\mathbb{Z}_{2^{32}}$**:
$$E' = a^{-1} \cdot \Big( (a \cdot E + b) \Big) - (a^{-1} \cdot b) \pmod{2^{32}}$$
where $a^{-1} \pmod{2^{32}}$ is computed via Newton-Raphson modular inverse iteration.

---

## 9. Linear Mixed Boolean-Arithmetic (MBA)
**Modules**: `lib/domain/services/native/mba_service.ml`, `lib/domain/services/c_source/c_mba_service.ml`

Linear MBA replaces arithmetic operations with equivalent bitwise formulas ($x + y \iff (x \oplus y) + 2(x \land y)$).

---

## 10. Control Flow Flattening (CFF)
**Modules**: `lib/domain/services/native/flattening_service.ml`, `lib/domain/services/c_source/c_flattening_service.ml`

Transforms high-level structured control flow into a flat, single-loop state machine dispatcher (`while(1) switch(__cff_state)`).

---

## 11. Invariant Opaque Predicates
**Modules**: `lib/domain/services/native/opaque_predicate_service.ml`, `lib/domain/services/c_source/c_opaque_service.ml`

Injects dead code branches guarded by algebraic tautologies ($(x \land \sim x) \neq 0$).

---

## 12. EncodeLiterals (String Literal Encryption)
**Module**: `lib/domain/services/c_source/c_encode_literals_service.ml`

Encrypts string literals at compile-time into byte arrays with lazy in-function runtime decryptors.

---

## 13. Variable Splitting & Data Encoding (`EncodeData`)
**Module**: `lib/domain/services/c_source/c_encode_data_service.ml`

Splits local scalar integer variables $v$ into two distinct variables $(v_{s1}, v_{s2})$: $v = v_{s1} + v_{s2}$.

---

## 14. C-Level Implicit Flow (Signals)
**Module**: `lib/domain/services/c_source/c_implicit_flow_service.ml`

Replaces explicit conditional jumps with signal-driven control flow via `NULL` dereference and `sigsetjmp` / `siglongjmp`.
