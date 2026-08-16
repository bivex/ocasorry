# ⚡ Vectis Virtual ISA Specification (v2)

The **Vectis Virtual Instruction Set Architecture (vISA v2)** is a custom, typed, RISC-style virtual machine architecture designed for high semantic density, dynamic state masking, and reverse-engineering resistance.

---

## 🔢 1. Opcodes & Instruction Set

The architecture specifies **18 core opcodes**:

| Opcode | Mnemonic | Format | Description |
|---|---|---|---|
| `0x01` | `MOV` | `vd, vs1` | Move register / immediate to destination |
| `0x02` | `ADD` | `vd, vs1, vs2` | 64-bit addition with overflow and carry flags |
| `0x03` | `SUB` | `vd, vs1, vs2` | 64-bit subtraction with borrow flags |
| `0x04` | `MUL` | `vd, vs1, vs2` | 64-bit unsigned/signed multiplication |
| `0x05` | `DIV` | `vd, vs1, vs2` | 64-bit unsigned division (safe trap on 0) |
| `0x06` | `MOD` | `vd, vs1, vs2` | 64-bit modulo remainder |
| `0x07` | `XOR` | `vd, vs1, vs2` | Bitwise Exclusive-OR |
| `0x08` | `AND` | `vd, vs1, vs2` | Bitwise AND |
| `0x09` | `OR`  | `vd, vs1, vs2` | Bitwise OR |
| `0x0A` | `SHL` | `vd, vs1, vs2` | Bitwise Logical Shift Left |
| `0x0B` | `SHR` | `vd, vs1, vs2` | Bitwise Logical Shift Right |
| `0x0C` | `ROL` | `vd, vs1, vs2` | Bitwise Rotate Left (64-bit circular) |
| `0x0D` | `ROR` | `vd, vs1, vs2` | Bitwise Rotate Right (64-bit circular) |
| `0x0E` | `CMP` | `vs1, vs2` | Compare values and update `ZF, NF, CF, VF` |
| `0x0F` | `TEST`| `vs1, vs2` | Logical compare `vs1 & vs2`, updates `ZF, NF` |
| `0x10` | `BRANCH`| `target` | Conditional branch based on condition code |
| `0x11` | `CALL` | `target` | Push return PC to call stack and jump |
| `0x12` | `RET`  | - | Pop PC from call stack and return |
| `0x13` | `LOAD` | `vd, [base + off]` | Read 64-bit value from memory table |
| `0x14` | `STORE`| `vs1, [base + off]`| Write 64-bit value to memory table |
| `0x15` | `SELECT`| `vd, vs1, vs2` | Conditional select based on flags |
| `0x16` | `JIT_EXEC`| `entry_id` | Invoke ephemeral JIT code page |
| `0x17` | `TAMPER_TRAP`| `code` | Controlled security shutdown trap |

---

## 🚩 2. Virtual Condition Flags

The VM tracks 4 architectural condition flags:

1. **ZF (Zero Flag)**: Set when result of operation is 0.
2. **NF (Negative Flag)**: Set when sign bit (bit 63) is 1.
3. **CF (Carry Flag)**: Set when unsigned addition overflows or subtraction borrows.
4. **VF (Overflow Flag)**: Set when signed two's complement arithmetic overflows.

Branch conditions (`cond_code`):
`ALWAYS`, `EQ` (ZF=1), `NE` (ZF=0), `LT` (NF≠VF), `LE` (ZF=1 or NF≠VF), `GT` (ZF=0 and NF=VF), `GE` (NF=VF).

---

## 🛡️ 3. Dynamic Algebraic State Masking

Physical register storage does not hold plaintext values. Every write to register $r$ at epoch $E$ is algebraically masked:

$$\text{Mask}(r, E) = \big(\text{base\_mask} + ((r + \text{rot\_seed}) \bmod 64) \times \text{step\_mask}\big) \oplus (E \times \text{0x9E3779B9})$$

$$\text{Physical\_Reg}[r] = \text{Logical\_Val} \oplus \text{Mask}(r, E)$$

When unmasking, the VM queries the register's recorded epoch tag $E_r$ and inverts the affine mask in $O(1)$.

---

## 🔄 4. VPC Stepper Modules

1. **LinearStepper**: Standard monotonic PC incrementation $PC_{n+1} = PC_n + 1$.
2. **NonlinearStepper (Anti-Pushan Quadratic Invariant)**:
   Computes next VPC offset using the invariant:
   $$\forall S \in \mathbb{Z}: \quad (S \times (S + 1)) \bmod 2 \equiv 0$$
   $$\text{Offset}(S) = 1 + ((S \times (S + 1)) \bmod 2) \equiv 1$$
   Any dynamic tampering during execution perturbs the invariant, causing execution to trap into an unrecoverable handler.
3. **RandomizedStepper**: Pseudo-random non-linear block hopping with table relocation.
