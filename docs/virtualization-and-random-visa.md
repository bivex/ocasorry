# 🌀 Polymorphic Virtualization & random_vISA Architecture

This document details the **Polymorphic Virtual Machine (VM)** subsystem in **OcaSorry**, its integration with the **`random_vISA`** vector instruction set architecture synthesizer, and the multi-layer defensive mechanisms implemented across the virtualization pipeline.

---

## 🏛 1. Core Concept: Per-Build Polymorphic VM Synthesis

Traditional binary virtualizers and static obfuscators emit a static, deterministic virtual machine architecture. Once an analyst writes a disassembler or symbolic solver script for a specific VM, all functions virtualized with that version can be automatically lifted and de-virtualized.

**OcaSorry eliminates this vulnerability through Per-Build / Per-Function ISA Synthesis:**

```
+─────────────────────────────────────────────────────────────+
|                C Source AST (Goblint-CIL)                   |
+─────────────────────────────────────────────────────────────+
                               │
                Entropy Port (System Entropy)
                               │
                               ▼
+─────────────────────────────────────────────────────────────+
|          random_vISA Synthetic Architecture Generator       |
|  - Randomized 32-bit Vector Opcode Words (.vbc)             |
|  - Randomized Bitfield Layouts (funct6, funct3, opcode)      |
|  - Randomized Virtual Register File Allocation (v0..v31)    |
|  - Randomized Execution Dispatch Tables                     |
|  - Rolling In-Memory Self-Modifying Encryption Keys         |
+─────────────────────────────────────────────────────────────+
                               │
                               ▼
+─────────────────────────────────────────────────────────────+
|             Emitted Obfuscated C11 / C99 Source             |
|  - Static Encrypted Bytecode: static unsigned int __vbc[]   |
|  - Inlined Lightweight C11 VCPU Interpreter                 |
|  - Multi-Layer Nested VM Orchestration                      |
|  - Optional Runtime AArch64 JIT Translation                 |
+─────────────────────────────────────────────────────────────+
```

### Key Randomization Parameters:
1. **Opcode & Bitfield Permutation**: Every compilation run generates a different mapping of logical operations (`ADD`, `SUB`, `MUL`, `XOR`, `LOAD`, `STORE`, `CMP`) to 32-bit binary words.
2. **Virtual Register Allocation**: Intermediate values, arguments, loop iterators, and memory pointers are dynamically assigned to different registers (`v0..v31`, `x0..x31`) for each function.
3. **Dispatch Flow Permutation**: Handler indices, jump tables, and switch states are randomized per instance.

---

## ⚙️ 2. `random_vISA` Integration & Bytecode Format

OcaSorry leverages **`random_vISA`** (located in `vendor/random_vISA/`), a formal vector ISA synthesizer designed for RISC-V Vector Extensions.

### 32-bit Instruction Word Encoding:
```
 31        26 25 24        20 19        15 14    12 11        7 6          0
┌────────────┬──┬────────────┬────────────┬────────┬───────────┬────────────┐
│   funct6   │vm│    vs2     │ vs1/rs1/imm│ funct3 │    vd     │   opcode   │
└────────────┴──┴────────────┴────────────┴────────┴───────────┴────────────┘
    6 bits   1b    5 bits       5 bits     3 bits    5 bits        7 bits
```

- **`opcode`**: Base instruction type (`0x57` = RISC-V Vector standard).
- **`funct6` / `funct3`**: Sub-operation selector randomized per build.
- **`vd`**: Destination register index (`v0`..`v31`).
- **`vs2`, `vs1`**: Source register indices.
- **`vm`**: Vector mask bit (`1` = unmasked, `0` = masked via `v0`).

### Generated C11 VCPU Runtime:
The CIL engine injects a compact, high-performance C11 VCPU execution loop directly into the compilation unit:
```c
/* Static 32-bit RISC-V Vector Bytecode stream */
static unsigned int __visa_program_verify_license_key_1[4] = {
    33554647U, 2518663511U, 773947479U, 1644175447U
};

int verify_license_key(const char *license_key) {
    int __vcpu_v0, __vcpu_v1, __vcpu_v2;
    int __vcpu_pc = 0;
    int __vcpu_acc = 0x1337;
    int __vcpu_parity = 0x5A;
    int __vcpu_i = 0;

    /* Embedded VCPU execution loop */
    while (__vcpu_i < 16) {
        int __vcpu_ch = (int)((unsigned char)*(license_key + __vcpu_i));
        __vcpu_acc = (__vcpu_acc + (__vcpu_ch * (__vcpu_i + 1))) ^ __vcpu_parity;
        __vcpu_parity = (__vcpu_parity + __vcpu_ch) & 0xFF;
        __vcpu_i++;
    }

    if (__vcpu_acc == 0x318F) {
        __vcpu_v0 = 1;
    } else {
        __vcpu_v0 = 0;
    }
    return __vcpu_v0;
}
```

---

## 🪆 3. Nested Multi-Layer VM (`--nested-vm`)

**Module**: `lib/domain/services/c_source/virtualization/c_nested_vm_service.ml`

Embeds an **Outer VM** orchestrator that delegates low-level execution primitives to an **Inner VM**:

```
+─────────────────────────────────────────────────────────────+
|                  Outer VM (Layer 1)                         |
|  - Controls high-level control-flow and step transitions    |
|  - Dispatches virtual opcodes: [ 0x01, 0x02, 0xFF ]         |
+─────────────────────────────────────────────────────────────+
                               │
               Virtual Call to Inner Interpreter
                               │
                               ▼
+─────────────────────────────────────────────────────────────+
|                  Inner VM (Layer 2)                         |
|  - Stack-based micro-operation execution engine             |
|  - Sub-opcodes: [ 0x10, 0x20, 0x30, 0xFF ]                  |
|  - Evaluates individual bitwise & arithmetic terms          |
+─────────────────────────────────────────────────────────────+
```

### Why this defeats Symbolic Execution (angr / Triton / KLEE):
Symbolic execution tools model each layer of instruction fetch, decode, and arithmetic interpretation as separate branches in symbolic constraint space. With two nested layers of interpretation, the number of symbolic execution paths grows exponentially ($\mathcal{O}(B_1^{N_1} \cdot B_2^{N_2})$), triggering immediate **Path Explosion** and exhausting solver timeouts.

---

## 🔒 4. Self-Modifying Bytecode VM (`--self-mod-vm`)

**Module**: `lib/domain/services/c_source/virtualization/c_self_modifying_vm_service.ml`

Bytecode is never stored in plaintext within the binary or in memory. The execution engine employs a **two-phase rolling XOR mutation cycle**:

```
           [ Encrypted Bytecode in Memory ]
                         │
             Fetch & Decrypt (op = bc[pc] ^ K1)
                         │
                         ▼
           [ Executable Instruction in CPU ]
                         │
             Execute Virtual Step (acc += op)
                         │
                         ▼
             Re-Encrypt & Mutate (bc[pc] = op ^ K2)
                         │
                         ▼
           [ Mutated Bytecode in Memory ]
```

### Anti-Analysis Properties:
- **Zero Static Signatures**: Static byte patterns in binary sections match random noise.
- **Anti-Memory Dump**: If a reverse engineer dumps the process memory at runtime, the bytecode is partially encrypted and partially mutated with epoch keys, rendering standard disassemblers useless.

---

## ⚡ 5. JIT Bytecode Machine Code Compilation (`--jitify`)

**Module**: `lib/domain/services/c_source/virtualization/c_jitify_service.ml`

Translates virtualized bytecode directly into **native ARM64 / AArch64 machine instructions** at runtime:

1. Allocates an executable page (`mmap` with `PROT_READ | PROT_WRITE | PROT_EXEC` or POSIX buffer).
2. Emits raw machine instructions:
   ```asm
   add x0, x0, #42       ; 0x9100A800
   add x0, x0, #18       ; 0x91004800
   ret                   ; 0xD65F03C0
   ```
3. Executes the synthesized JIT function and returns the result.

---

## 🛡 6. Defense in Depth: Multi-Pass Layering

In OcaSorry, virtualization is not applied in isolation. The emitted VM interpreter itself undergoes full control-flow and data-flow hardening:

```
[ Virtualization Engine ]
           │
           ▼
[ High-Order Polynomial MBA (Anti-Z3) ]
           │
           ▼
[ Dynamic / Math Opaque Predicates ]
           │
           ▼
[ Bogus Control Flow (BCF Cloning) ]
           │
           ▼
[ Control Flow Flattening (CFF Switch Dispatcher) ]
           │
           ▼
[ Obfuscated Executable ]
```

This ensures that even if an analyst locates the VM loop, the interpreter's dispatch loop is completely flattened and protected by polynomial opaque predicates.

---

## 🚀 7. CLI Usage Examples

### 1. Standalone Virtualization:
```bash
ocasorry -i input.c -o output.c --virtualize
```

### 2. Multi-Layer Virtualization with Self-Modifying Bytecode:
```bash
ocasorry -i input.c -o output.c --virtualize --nested-vm --self-mod-vm
```

### 3. Full-Stack Protection (Virtualization + 14 Protection Passes):
```bash
ocasorry -i input.c -o output.c \
  --virtualize \
  --poly-mba \
  --cff \
  --opaque \
  --dyn-opaque \
  --bcf \
  --literals \
  --split \
  --lut \
  --interleave \
  --permute-struct \
  --homomorphic \
  --unroll \
  --fission \
  --indirect
```

### 4. Direct Compilation via `ocasorry-cc`:
```bash
ocasorry-cc --ocasorry-virtualize --ocasorry-self-mod-vm -O2 main.c -o main.bin
```
