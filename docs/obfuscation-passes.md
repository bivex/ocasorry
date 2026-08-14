# Obfuscation Techniques & Passes

This document details the transformation algorithms implemented in **OcaSorry**.

---

## 1. Mixed Boolean-Arithmetic (MBA)
**Modules**: `lib/domain/services/native/mba_service.ml`, `lib/domain/services/c_source/c_mba_service.ml`

MBA replaces simple arithmetic operations with complex, mathematically equivalent Boolean and bitwise expressions.

### Linear MBA Identities:
- **Addition ($x + y$)**:
  - $(x \oplus y) + 2(x \land y)$
  - $(x \lor y) + (x \land y)$
  - $2(x \lor y) - (x \oplus y)$
- **Subtraction ($x - y$)**:
  - $(x \oplus y) - 2(\sim x \land y)$
  - $(x \land \sim y) - (\sim x \land y)$
- **Bitwise XOR ($x \oplus y$)**:
  - $(x \lor y) - (x \land y)$
  - $(x \lor y) + (\sim x \land \sim y) - (-1)$

---

## 2. Control Flow Flattening (CFF)
**Modules**: `lib/domain/services/native/flattening_service.ml`, `lib/domain/services/c_source/c_flattening_service.ml`

Transforms high-level structured control flow (nested `if`, `while`, `for`) into a flat, single-loop state machine dispatcher:
1. Basic blocks are assigned pseudo-random state IDs.
2. The function body is placed inside a `while(1) switch(__cff_state)` construct.
3. Execution order is shuffled randomly in the AST, completely destroying the visual graph hierarchy in decompilers (IDA, Ghidra).

---

## 3. Invariant Opaque Predicates
**Modules**: `lib/domain/services/native/opaque_predicate_service.ml`, `lib/domain/services/c_source/c_opaque_service.ml`

Injects dead code branches guarded by algebraic tautologies:
- Condition: $(x \land \sim x) \neq 0$ (Guaranteed `false` for any signed or unsigned integer).
- The `true` branch is populated with junk code, deceptive instruction sequences, or invalid opcodes that confuse static disassemblers without ever executing.

---

## 4. EncodeLiterals (String Literal Encryption)
**Module**: `lib/domain/services/c_source/c_encode_literals_service.ml`

- Detects string constants in C AST (`Const (CStr "...")`).
- Encrypts each character at compile-time with a generated key: $E[i] = S[i] \oplus K$.
- Replaces string constants with pointers to static byte arrays: `static char __enc_lit_X[]`.
- Injects a lazy runtime decryptor guard in the function prologue:
  ```c
  static int __init_lit_1 = 0;
  if (!__init_lit_1) {
      for (int i = 0; i < len; i++) {
          __dec_lit_1[i] = __enc_lit_1[i] ^ key;
      }
      __init_lit_1 = 1;
  }
  ```
- Strips open-text strings completely from the executable `.rodata` section.

---

## 5. Variable Splitting & Data Encoding (`EncodeData`)
**Module**: `lib/domain/services/c_source/c_encode_data_service.ml`

Splits local scalar integer variables $v$ into two distinct variables $(v_{s1}, v_{s2})$:
- Invariant maintained at all times: $v = v_{s1} + v_{s2}$.
- Assignment $v = \text{expr}$ is rewritten as:
  $$\text{temp} = \text{expr}, \quad v_{s2} = \text{temp} \gg 1, \quad v_{s1} = \text{temp} - (\text{temp} \gg 1)$$
- Every read access to $v$ becomes $(v_{s1} + v_{s2})$.
- Prevents memory scanning tools and symbolic execution engines from tracking the true variable value.

---

## 6. C-Level Implicit Flow (Signals)
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
