# Obfuscation Techniques & Passes

This document details the transformation algorithms implemented in **OcaSorry**.

---

## 1. Lookup Table Arithmetic (LUT)
**Module**: `lib/domain/services/c_source/data_encoding/c_lut_arithmetic_service.ml`

Converts arithmetic and bitwise byte operations into static 256-element lookup tables (`static const unsigned char __lut_xor_K[256]`):
```c
/* x ^ 0x5A becomes: */
__lut_xor_5A_1[x & 0xFF];
```

---

## 2. Array Folding & Interleaving
**Module**: `lib/domain/services/c_source/data_encoding/c_array_interleave_service.ml`

Transforms array index lookups by wrapping indices into non-trivial scaled interleaved expressions (`((idx << 1) - idx)`), preventing linear dataflow and cache locality tracking.

---

## 3. Struct Field Permutation & Padding
**Module**: `lib/domain/services/c_source/data_encoding/c_struct_permute_service.ml`

Reorders fields in structure definitions (`CompInfo`) and injects random padding fields (`int __pad_field_1;`), destroying struct layout assumptions in Ghidra / IDA Pro.

---

## 4. Pointer Swizzling & Pointer Masking
**Module**: `lib/domain/services/c_source/data_encoding/c_pointer_masking_service.ml`

Applies reversible XOR masking layers to pointer addresses at dereference sites (`*( (type*) (((uintptr_t)ptr ^ MASK) ^ MASK) )`), confounding dynamic taint tracking and automated pointer analyzers.

---

## 5. Homomorphic Data Encoding
**Module**: `lib/domain/services/c_source/data_encoding/c_homomorphic_service.ml`

Encodes scalar values into $x_H = (a \cdot x + b) \bmod 2^{32}$. Arithmetic operations $(+, -, *)$ proceed directly in the encoded domain without intermediate decoding until output points.

---

## 6. Dynamic / Math-Property Opaque Predicates
**Module**: `lib/domain/services/c_source/control_flow/c_dynamic_opaque_service.ml`

Generates dynamic invariants based on integer arithmetic properties:
- $(x \cdot (x + 1)) \bmod 2 = 0$ (Always True for any integer $x$).
- $((x \ll 2) + 2) \bmod 2 = 0$ (Always True for any integer $x$).
- $(x \mid 1) \bmod 2 \neq 0$ (Always True for any integer $x$).

---

## 7. Bogus Control Flow (BCF Code Cloning & Mutation)
**Module**: `lib/domain/services/c_source/control_flow/c_bogus_control_flow_service.ml`

Clones legitimate basic blocks, alters numeric constants in the duplicate, and guards the paths behind a Dynamic Opaque Predicate.

---

## 8. Loop Unrolling & Jittering
**Module**: `lib/domain/services/c_source/control_flow/c_loop_unroll_service.ml`

Unrolls loop bodies by a factor of 2 while interleaving non-interfering jitter computations (`__loop_jitter = (__loop_jitter * 31) ^ 0x5A`).

---

## 9. Loop Fission & Segmentation
**Module**: `lib/domain/services/c_source/control_flow/c_loop_fission_service.ml`

Splits multi-statement loop bodies into sequenced execution phases (`__loop_phase`), breaking loop invariant analysis.

---

## 10. Indirect Jump Tables (Computed Dispatch)
**Module**: `lib/domain/services/c_source/control_flow/c_indirect_jump_service.ml`

Converts sequential statement blocks into an indirect indexed dispatch table (`switch(__indirect_state)`), breaking linear code layout.

---

## 11. Function Merging (`Merge`)
**Module**: `lib/domain/services/c_source/c_merge_functions_service.ml`

Merges pairs of independent C functions into a monolithic dispatcher function `__merged_fn(selector, ...)`.

---

## 12. Function Outlining (`Outline`)
**Module**: `lib/domain/services/c_source/c_outline_service.ml`

Slices contiguous statement blocks from function bodies into separate `static` helper functions passing local variables via pointer references.

---

## 13. High-Order Polynomial MBA & Invertible Affine Transformations (Anti-Z3)
**Module**: `lib/domain/services/c_source/c_polynomial_mba_service.ml`

Generates non-linear polynomial expressions coupled with **Invertible Affine Layers over $\mathbb{Z}_{2^{32}}$**:
$$E' = a^{-1} \cdot \Big( (a \cdot E + b) \Big) - (a^{-1} \cdot b) \pmod{2^{32}}$$
where $a^{-1} \pmod{2^{32}}$ is computed via Newton-Raphson modular inverse iteration.

---

## 14. Linear Mixed Boolean-Arithmetic (MBA)
**Modules**: `lib/domain/services/native/mba_service.ml`, `lib/domain/services/c_source/c_mba_service.ml`

Linear MBA replaces arithmetic operations with equivalent bitwise formulas ($x + y \iff (x \oplus y) + 2(x \land y)$).

---

## 15. Control Flow Flattening (CFF)
**Modules**: `lib/domain/services/native/flattening_service.ml`, `lib/domain/services/c_source/c_flattening_service.ml`

Transforms high-level structured control flow into a flat, single-loop state machine dispatcher (`while(1) switch(__cff_state)`).

---

## 16. Invariant Opaque Predicates
**Modules**: `lib/domain/services/native/opaque_predicate_service.ml`, `lib/domain/services/c_source/c_opaque_service.ml`

Injects dead code branches guarded by algebraic tautologies ($(x \land \sim x) \neq 0$).

---

## 17. EncodeLiterals (String Literal Encryption)
**Module**: `lib/domain/services/c_source/c_encode_literals_service.ml`

Encrypts string literals at compile-time into byte arrays with lazy in-function runtime decryptors.

---

## 18. Variable Splitting & Data Encoding (`EncodeData`)
**Module**: `lib/domain/services/c_source/c_encode_data_service.ml`

Splits local scalar integer variables $v$ into two distinct variables $(v_{s1}, v_{s2})$: $v = v_{s1} + v_{s2}$.

---

## 19. C-Level Implicit Flow (Signals)
**Module**: `lib/domain/services/c_source/c_implicit_flow_service.ml`

Replaces explicit conditional jumps with signal-driven control flow via `NULL` dereference and `sigsetjmp` / `siglongjmp`.
