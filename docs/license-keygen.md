# 🔑 License Keygen: 4-VCPU Cascade Mathematics & Tools

This document covers the license key generation and verification system in **Vectis**, including the mathematical cascade equations, the meet-in-the-middle suffix solver algorithm, and the complete CLI reference for both the Python and C keygen tools.

---

## 📖 Overview

A valid Vectis license key is a **16-character ASCII string** composed of uppercase letters (`A–Z`) and digits (`0–9`). Validity is determined by cascading the key through all **4 federated virtual processor tiers**:

```
License Key (16 chars)
        │
        ▼
  VCPU 1 (random_vISA Vector Processor)
        │ h1 = vcpu1_vector_parity(key) == 12687
        ▼
  VCPU 2 (Nested 2-Tier Hierarchical VM)
        │ h2 = h1 + 21 == 12708
        ▼
  VCPU 3 (Stateful Rolling Key VM)
        │ h3 = ((h2 + 10) ^ 42) * 2 == 25352
        ▼
  VCPU 4 (In-Memory Ephemeral JIT VM)
        │ is_valid = (h3 == 25352) → 1 (UNLOCKED)
        ▼
    ACCEPT / REJECT
```

---

## 🧮 Cascade Equations

### VCPU 1 — `random_vISA` Vector Processor

Computes a **positional weighted accumulator with rolling XOR parity**:

$$
h_1 = \text{VCPU}_1(\text{key}) = \bigoplus_{i=0}^{15} \Bigl[ \text{acc} \mathrel{+}= \text{key}[i] \times (i+1) \Bigr]
$$

More precisely, using the initial state `acc = 0x1337`, `parity = 0x5A`:

$$
\text{acc}_{i+1} = \bigl(\text{acc}_i + \text{key}[i] \times (i+1)\bigr) \oplus \text{parity}_i
$$
$$
\text{parity}_{i+1} = (\text{parity}_i + \text{key}[i]) \bmod 256
$$

**Target**: `h1 = acc16 = 12687` (decimal) = `0x318F`

### VCPU 2 — Nested Hierarchical VM

Applies a simple linear outer-layer transform on `h1`:

$$
h_2 = \text{VCPU}_2(h_1) = h_1 + 21 = 12708
$$

**Target**: `h2 = 12708`

### VCPU 3 — Stateful Rolling Key VM

Applies an **add-XOR-multiply** non-linear transform on `h2`:

$$
h_3 = \text{VCPU}_3(h_2) = \bigl((h_2 + 10) \oplus 42\bigr) \times 2
$$

With `h2 = 12708`:
$$
h_3 = ((12708 + 10) \oplus 42) \times 2 = (12718 \oplus 42) \times 2 = 12676 \times 2 = 25352
$$

**Target**: `h3 = 25352`

### VCPU 4 — Ephemeral JIT VM

Binary validation gate — allocates anonymous RAM, decrypts payload, executes verification, and immediately wipes memory:

$$
\text{is\_valid} = \text{VCPU}_4(h_3) = \begin{cases} 1 & \text{if } h_3 = 25352 \\ 0 & \text{otherwise} \end{cases}
$$

---

## ⚙️ Meet-in-the-Middle Suffix Solver

Brute-forcing a 16-character key over a 36-character alphabet (`A-Z0-9`) gives $36^{16} \approx 7.96 \times 10^{24}$ combinations — computationally infeasible.

Vectis's keygen uses a **meet-in-the-middle suffix attack** that reduces the search to $\mathcal{O}(N \times 36^2)$ where $N$ is the number of random body attempts:

### Algorithm

```
Input:  prefix (e.g. "PRO-"), key length = 16
Output: 16-char valid key

1. Compute body_len = 16 - len(prefix) - 2
   (reserve last 2 characters as the "solved suffix")

2. Repeat until found:
   a. Generate random body: random_body = random chars of length body_len
      candidate_base = prefix + random_body  (14 chars total)

   b. Partially compute VCPU 1 state over candidate_base (positions 0..13):
      acc, parity = vcpu1_partial(candidate_base)

   c. Exhaustive 2-character inner search (36 × 36 = 1296 combinations):
      for c1 in ALPHABET:
          acc1 = (acc  + ord(c1) * 15) ^ parity
          par1 = (parity + ord(c1)) & 0xFF
          for c2 in ALPHABET:
              acc2 = (acc1 + ord(c2) * 16) ^ par1
              if acc2 == TARGET_H1 (12687):
                  return candidate_base + c1 + c2  ← VALID KEY
```

### Complexity

- **Inner loop**: Always at most 1,296 iterations per body attempt.
- **Expected outer iterations**: Empirically ~1–5 random body attempts per valid key found.
- **Total per-key cost**: ~O(6,000) hash evaluations on average.
- **Python runtime**: < 1ms per key on modern hardware.

### Key Format

```
┌──────────┬───────────────────────────────────┬────────────────┐
│  PREFIX  │           RANDOM BODY             │ SOLVED SUFFIX  │
│  4 chars │          10 chars                 │    2 chars     │
└──────────┴───────────────────────────────────┴────────────────┘
   "PRO-"      e.g. "9842-KLM9-"               e.g. "77"
                              Total = 16 characters
```

---

## 🐍 Python Keygen: `tools/license_keygen.py`

### Synopsis

```bash
python3 tools/license_keygen.py [OPTIONS]
```

### Flags

| Flag | Short | Type | Default | Description |
| :--- | :---: | :--- | :--- | :--- |
| `--count` | `-n` | `int` | `1` | Number of valid license keys to generate |
| `--prefix` | `-p` | `str` | `"PRO-"` | Key tier prefix (e.g. `PRO-`, `ENT-`, `DEV-`, `ULT-`) |
| `--check` | `-c` | `str` | — | Validate and trace an existing license key |
| `--json` | `-j` | flag | `false` | Output results in JSON format |
| `--output` | `-o` | `str` | — | Save generated keys to a file (one per line) |
| `--verify` | `-v` | flag | `false` | Print detailed 4-VCPU trace for each generated key |

### Examples

```bash
# Generate 5 PRO keys with full 4-VCPU trace
python3 tools/license_keygen.py -n 5 --prefix PRO- --verify

# Generate 10 Enterprise keys as JSON, save to file
python3 tools/license_keygen.py -n 10 --prefix ENT- --json --output ent_keys.txt

# Validate and trace a specific key
python3 tools/license_keygen.py --check "PRO-9842-KLM9-77"

# Generate keys with JSON output (machine-readable)
python3 tools/license_keygen.py -n 3 --prefix DEV- --json --verify
```

### Example Output

```
=================================================================
   Vectis 4-VCPU License Keygen (5 keys generated in 2.3ms)
=================================================================
  [01] PRO-9842KLM977AB  -> [h1=12687, h2=12708, h3=25352 | VALID]
  [02] PRO-X71RQWZ9M4FG  -> [h1=12687, h2=12708, h3=25352 | VALID]
  [03] PRO-2KJ8BNVP06LC  -> [h1=12687, h2=12708, h3=25352 | VALID]
  [04] PRO-YT5CHSG3RZWP  -> [h1=12687, h2=12708, h3=25352 | VALID]
  [05] PRO-08DMNEA7VXJQ  -> [h1=12687, h2=12708, h3=25352 | VALID]
=================================================================
```

### Validation Output (`--check`)

```
=================================================================
       Vectis 4-VCPU Key Verification: PRO-9842-KLM9-77
=================================================================
  Length        : 16 / 16 chars
  VCPU 1 (h1)   : 12687 (Target: 12687)
  VCPU 2 (h2)   : 12708 (Target: 12708)
  VCPU 3 (h3)   : 25352 (Target: 25352)
  VCPU 4 Result : UNLOCKED (Valid Key)
=================================================================
```

### JSON Output (`--json --verify`)

```json
{
  "generated_count": 1,
  "generation_time_ms": 1.42,
  "keys": [
    {
      "key": "PRO-9842KLM977AB",
      "length": 16,
      "vcpu1_h1": 12687,
      "vcpu1_target": 12687,
      "vcpu2_h2": 12708,
      "vcpu2_target": 12708,
      "vcpu3_h3": 25352,
      "vcpu3_target": 25352,
      "is_valid": true,
      "status": "UNLOCKED (Valid Key)"
    }
  ]
}
```

---

## ⚙️ C Keygen: `examples/01_keygen_tool.c`

A **native C implementation** of the same meet-in-the-middle keygen and verifier.

### Build

```bash
cd examples && make
# or: clang -O2 01_keygen_tool.c -o 01_keygen_tool.bin
```

### Usage

```bash
# Generate <count> valid keys with optional prefix
./examples/01_keygen_tool.bin <count> <prefix>

# Verify a specific key with full 4-VCPU trace
./examples/01_keygen_tool.bin --check <license_key>
```

### Examples

```bash
# Generate 5 PRO- keys
./examples/01_keygen_tool.bin 5 "PRO-"

# Generate 3 ULT- tier keys
./examples/01_keygen_tool.bin 3 "ULT-"

# Verify a key
./examples/01_keygen_tool.bin --check "PRO-9842-KLM9-77"
```

### Example Output

```
=================================================================
   Vectis Native C Keygen (5 keys generated with prefix 'PRO-')
=================================================================
  [01] PRO-9842KLM977AB  -> [4-VCPU Verified: VALID]
  [02] PRO-X71RQWZ9M4FG  -> [4-VCPU Verified: VALID]
  [03] PRO-2KJ8BNVP06LC  -> [4-VCPU Verified: VALID]
  [04] PRO-YT5CHSG3RZWP  -> [4-VCPU Verified: VALID]
  [05] PRO-08DMNEA7VXJQ  -> [4-VCPU Verified: VALID]
=================================================================
```

### C Implementation of the Cascade

The C tool implements the same VCPU functions as `tools/license_keygen.py`:

```c
// VCPU 1: positional weighted accumulator with rolling XOR parity
int vcpu1_vector_parity(const char *key) {
    int acc = 0x1337, parity = 0x5A;
    for (int i = 0; i < 16; i++) {
        int ch = (int)((unsigned char)key[i]);
        acc = (acc + (ch * (i + 1))) ^ parity;
        parity = (parity + ch) & 0xFF;
    }
    return acc;  // must equal 12687 (0x318F)
}

// VCPU 2: nested VM linear transform
int vcpu2_nested_matrix(int h1)  { return h1 + 21; }

// VCPU 3: rolling key add-XOR-multiply
int vcpu3_rolling_vkey(int h2)   { return ((h2 + 10) ^ 42) * 2; }

// VCPU 4: ephemeral JIT binary gate
int vcpu4_ephemeral_jit(int h3)  { return (h3 == 25352) ? 1 : 0; }
```

The **meet-in-the-middle suffix solver** in C exhausts all 36×36 = 1,296 two-character tail combinations per random body attempt:

```c
// Partial state after first 14 characters
for (int i1 = 0; i1 < ALPHABET_LEN; i1++) {
    int acc1 = (acc + (ALPHABET[i1] * 15)) ^ parity;
    int par1 = (parity + ALPHABET[i1]) & 0xFF;
    for (int i2 = 0; i2 < ALPHABET_LEN; i2++) {
        int acc2 = (acc1 + (ALPHABET[i2] * 16)) ^ par1;
        if (acc2 == TARGET_H1) {   // found valid suffix
            base[14] = ALPHABET[i1];
            base[15] = ALPHABET[i2];
            return;
        }
    }
}
```

---

## 🛡️ Security Properties

### One-Way Forward Direction

The 4-VCPU cascade computes `is_valid` as a **binary decision** — it does not expose the intermediate hash values `h1`, `h2`, `h3` to the caller. In the protected binary (`01_license_keygen_virtualized.bin`):

- VCPU 1 logic is compiled into an encrypted 32-bit vector bytecode stream (`static unsigned int __visa_program_*[]`).
- VCPU 2 is wrapped in a nested 2-tier interpreter with independent rolling keys.
- VCPU 3 is protected by the stateful rolling key recurrence, which diverges if any bytecode is patched.
- VCPU 4 runs in an anonymous RAM page that is **zeroed and unmapped immediately** after execution.

### Difficulty of Reversal

Finding a key without `tools/license_keygen.py` or `01_keygen_tool.c` requires:

1. **Defeating VCPU 1 virtualization**: Recovering the `acc` accumulator target `0x318F` requires extracting the bytecode from an encrypted, per-instruction rolling-XOR-decrypted stream.
2. **Defeating VCPU 2**: Symbolically tracking the outer/inner nested VM state machines through independent rolling key layers.
3. **Defeating VCPU 3**: Resynchronizing the stateful rolling key recurrence — any desync causes all subsequent decrypt operations to produce garbage.
4. **Defeating VCPU 4**: Capturing the ephemeral page before `memset(0)` / `munmap` — requires a hardware memory bus monitor or active `SIGSEGV`-based hooking.

Additionally, the protected binary applies a further 10 protection passes (CFF, BCF, Anti-Debug, Timing Checks, Symbol Renaming, etc.) via `build_license_demo.sh`, making the cascade's structure invisible to decompilers.

---

## 🔗 Related Documentation

- [docs/4-vcpu-federated-virtualization.md](4-vcpu-federated-virtualization.md) — Full 4-tier architecture and Sail ISA pipeline
- [docs/virtualization-and-random-visa.md](virtualization-and-random-visa.md) — random_vISA vector ISA internals
- [tools/license_keygen.py](../tools/license_keygen.py) — Python keygen source
- [examples/01_keygen_tool.c](../examples/01_keygen_tool.c) — C keygen source
- [examples/01_license_keygen.c](../examples/01_license_keygen.c) — Primary 4-VCPU demo target
