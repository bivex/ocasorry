# Obfuscation Techniques & Passes

This document details the transformation algorithms implemented in **OcaSorry**.

---

## 1. High-Order Polynomial MBA & Invertible Affine Transformations (Anti-Z3)
**Module**: `lib/domain/services/c_source/c_polynomial_mba_service.ml`

Linear MBA can sometimes be simplified by modern SMT-based deobfuscators (e.g. arybo, msynth, Z3). **OcaSorry** generates **High-Order Polynomial MBA expressions** coupled with **Invertible Affine Layers over the ring $\mathbb{Z}_{2^{32}}$**, causing combinatorial state-space explosion in symbolic solvers.

### Invertible Affine Layer over $\mathbb{Z}_{2^{32}}$:
For an expression $E$, an odd multiplier $a$ ($\gcd(a, 2^{32}) = 1$), and a random constant $b$:
1. We compute modular multiplicative inverse $a^{-1} \pmod{2^{32}}$ via Newton-Raphson iteration:
   $$x_{k+1} = x_k \cdot (2 - a \cdot x_k) \pmod{2^{32}}$$
2. Wrap $E$ in an affine permutation layer:
   $$E' = a^{-1} \cdot \Big( (a \cdot E + b) - b \Big) \pmod{2^{32}}$$
3. Substitute inner operations with non-linear polynomial identities.

### High-Order Polynomial Identities:
- **Non-Linear Addition ($x + y$)**:
  - $a^{-1} \cdot \Big( a \cdot \big( (x \oplus y) + 2(x \land y) \big) + b - b \Big)$
  - $a^{-1} \cdot \Big( a \cdot \big( 2(x \lor y) - (x \oplus y) \big) + b - b \Big)$
  - $a^{-1} \cdot \Big( a \cdot \big( (x \lor y) + (x \land y) \big) + b - b \Big)$
- **Non-Linear Subtraction ($x - y$)**:
  - $a^{-1} \cdot \Big( a \cdot \big( (x \oplus y) - 2(\sim x \land y) \big) + b - b \Big)$
  - $a^{-1} \cdot \Big( a \cdot \big( (x \land \sim y) - (\sim x \land y) \big) + b - b \Big)$
- **Non-Linear Bitwise XOR ($x \oplus y$)**:
  - $a^{-1} \cdot \Big( a \cdot \big( (x \lor y) - (x \land y) \big) + b - b \Big)$
  - $a^{-1} \cdot \Big( a \cdot \big( (x \lor y) + (\sim x \land \sim y) + 1 \big) + b - b \Big)$

---

## 2. Linear Mixed Boolean-Arithmetic (MBA)
**Modules**: `lib/domain/services/native/mba_service.ml`, `lib/domain/services/c_source/c_mba_service.ml`

Linear MBA replaces arithmetic operations with equivalent bitwise formulas:
- $x + y \iff (x \oplus y) + 2(x \land y)$
- $x + y \iff (x \lor y) + (x \land y)$
- $x + y \iff 2(x \lor y) - (x \oplus y)$
- $x - y \iff (x \oplus y) - 2(\sim x \land y)$
- $x \oplus y \iff (x \lor y) - (x \land y)$

---

## 3. Control Flow Flattening (CFF)
**Modules**: `lib/domain/services/native/flattening_service.ml`, `lib/domain/services/c_source/c_flattening_service.ml`

Transforms high-level structured control flow (nested `if`, `while`, `for`) into a flat, single-loop state machine dispatcher:
1. Basic blocks are assigned pseudo-random state IDs.
2. The function body is placed inside a `while(1) switch(__cff_state)` construct.
3. Execution order is shuffled randomly in the AST, completely destroying the visual graph hierarchy in decompilers (IDA, Ghidra).

---

## 4. Invariant Opaque Predicates
**Modules**: `lib/domain/services/native/opaque_predicate_service.ml`, `lib/domain/services/c_source/c_opaque_service.ml`

Injects dead code branches guarded by algebraic tautologies:
- Condition: $(x \land \sim x) \neq 0$ (Guaranteed `false` for any signed or unsigned integer).
- The `true` branch is populated with junk code, deceptive instruction sequences, or invalid opcodes that confuse static disassemblers without ever executing.

---

## 5. EncodeLiterals (String Literal Encryption)
**Module**: `lib/domain/services/c_source/c_encode_literals_service.ml`

- Detects string constants in C AST (`Const (CStr "...")`).
- Encrypts each character at compile-time with a generated key: $E[i] = S[i] \oplus K$.
- Replaces string constants with pointers to static byte arrays: `static char __enc_lit_X[]`.
- Injects a lazy runtime decryptor guard in the function prologue, stripping open-text strings completely from the executable `.rodata` section.

---

## 6. Variable Splitting & Data Encoding (`EncodeData`)
**Module**: `lib/domain/services/c_source/c_encode_data_service.ml`

Splits local scalar integer variables $v$ into two distinct variables $(v_{s1}, v_{s2})$:
- Invariant maintained at all times: $v = v_{s1} + v_{s2}$.
- Assignment $v = \text{expr}$ is rewritten as:
  $$\text{temp} = \text{expr}, \quad v_{s2} = \text{temp} \gg 1, \quad v_{s1} = \text{temp} - (\text{temp} \gg 1)$$
- Every read access to $v$ becomes $(v_{s1} + v_{s2})$.

---

## 7. C-Level Implicit Flow (Signals)
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
Decompilers and symbolic execution solvers treat the `NULL` write as an irrecoverable crash path, completely severing the link to the `then` block.
