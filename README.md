# OcaSorry

**OcaSorry** is an advanced **C source-to-source obfuscator** and **4-VCPU federated virtualization engine** written in **OCaml 5**, engineered following **Domain-Driven Design (DDD)** and **Hexagonal Architecture (Ports & Adapters)**.

It combines **C Source AST transformations** (powered by George Necula's [CIL / Goblint-CIL](https://github.com/goblint/cil)) with a **4-Tier Cascading Virtual Processor Pipeline**, a **drop-in compiler wrapper (`ocasorry-cc`)**, a **native AArch64 JIT emitter**, and formal **Sail ISA specifications** synthesized per build by the native DDD engine (`ocasorry-synth`).

---

## 📚 Documentation Index

| Document | Description |
| :--- | :--- |
| 🏛️ [Architecture](docs/architecture.md) | Hexagonal layer partitioning, Entities, Ports (SPI), Domain Services |
| 🛡️ [4-VCPU Federated Virtualization](docs/4-vcpu-federated-virtualization.md) | 4-Tier VCPU cascade, Sail ISA pipeline, keygen mathematics |
| 🌀 [Polymorphic Virtualization & random_vISA](docs/virtualization-and-random-visa.md) | Per-build synthetic vector ISA, nested VM, self-modifying bytecode, JIT |
| ⚡ [Obfuscation Passes & Math](docs/obfuscation-passes.md) | All 56+ transformation passes with equations and module references |
| 🔑 [License Keygen Documentation](docs/license-keygen.md) | 4-VCPU cascade math, meet-in-the-middle solver, Python & C keygen tools |
| 🧬 [ISA Generation Pipeline](docs/isa-generation-pipeline.md) | End-to-end architectural guide: Sail/JSON synthesis to target C11 runtime |
| 🔄 [Two-Level JIT & Hardware Signal Flow](docs/two-tier-jit.md) | Staging architecture, Apple Silicon W^X cache, `ucontext_t` PC redirection |
| 🛠️ [Compiler Wrapper (`ocasorry-cc`)](docs/compiler-wrapper.md) | Integration guide: Makefiles, CMake, flags, options |
| 📋 [CIL Capabilities & Roadmap](docs/cil-capabilities.md) | Complete checkbox roadmap of all 61+ techniques via Goblint-CIL |
| 🗒️ [Code Morphing TODO](docs/code-morphing-todo.md) | Planned morphing and anti-analysis enhancements |

---

## 🎯 Why OCaml + CIL Instead of LLVM?

| Problem with LLVM | Advantage of OCaml + CIL (OcaSorry) |
| :--- | :--- |
| **Normalizing IR**: LLVM canonicalizes control flow, removes dead code, and un-obfuscates opaque predicates | **AST Preservation**: CIL AST retains intentional entropy, dead branches, and complex structures |
| **Heavy Dependency**: Requires massive toolchain (hundreds of MB–GB) | **Lightweight & Fast**: Pure OCaml with algebraic data types and minimal runtime footprint |
| **Hardware Tricks**: Difficult to emit signal traps and custom inline dispatchers | **Full Low-Level Control**: Native support for `SIGSEGV`/`SIGTRAP`, `mmap(MAP_JIT)`, raw AArch64 byte synthesis |

---

## 🏗️ 4-Tier VCPU Cascade

OcaSorry virtualizes C functions through a 4-tier federated virtual processor pipeline. Each tier executes a distinct computational role:

| Tier | Type | Annotation | Sail Spec |
| :---: | :--- | :--- | :--- |
| 1 | `random_vISA` — 32-bit Vector ISA | `ocasorry:visa` | [`vcpu1_visa.sail`](examples/vcpu1_visa.sail) |
| 2 | `nested_vm` — 2-Tier Hierarchical VM | `ocasorry:nested_vm` | [`vcpu2_nested_vm.sail`](examples/vcpu2_nested_vm.sail) |
| 3 | `rolling_vkey` — Stateful Rolling Key VM | `ocasorry:rolling_vkey` | [`vcpu3_rolling_vkey.sail`](examples/vcpu3_rolling_vkey.sail) |
| 4 | `ephemeral_jit` — In-Memory Ephemeral JIT Wiper | `ocasorry:ephemeral` | [`vcpu4_ephemeral_jit.sail`](examples/vcpu4_ephemeral_jit.sail) |

> See [docs/4-vcpu-federated-virtualization.md](docs/4-vcpu-federated-virtualization.md) for the full architecture and keygen math.

---

## ⚡ Key Capabilities — 61+ Obfuscation Passes

### Virtualization & Custom Interpreters

| Pass | Description |
| :--- | :--- |
| `Virtualize` (random_vISA) | Encodes functions into 32-bit RISC-V Vector bytecode with embedded C11 VCPU loop |
| `NestedVM` | 2-tier hierarchical outer/inner interpreter with independent rolling keys |
| `SelfModVM` | Rolling XOR fetch-decrypt-re-encrypt bytecode mutation cycle |
| `Jitify` | Runtime AArch64 machine code generator from virtualized bytecode |
| `RollingVKey` | Stateful decryption key tied strictly to execution history |
| `EphemeralPayload` | `mmap` → decrypt → execute → `memset(0)` → `munmap` ephemeral payload |
| `VCPUContextScramble` | Per-build field-order randomization of `struct __vcpu_state` |
| `DecentDisp` (Anti-VMTag) | Binary decision tree dispatcher with unsolvable Diophantine decoy hub |

### Control-Flow Obfuscation

| Pass | Description |
| :--- | :--- |
| `CFF` | Control Flow Flattening into `while(1) switch(__cff_state)` |
| `IrreducibleCFG` | Multi-entry irreducible loops defeating Phoenix / NoMoreGotos |
| `BCF` | Bogus Control Flow: real block cloned + guarded by opaque predicate |
| `OpaqueInvariant` | Algebraic tautologies: `(x & ~x) == 0` |
| `OpaqueDynamic` | Math-property invariants: `(x*(x+1)) % 2 == 0` |
| `OpaqueDiophantine` | Unsolvable integer equations: `x^2 ≡ 2 (mod 4)` |
| `BBSplit` | Basic block splitting via explicit `goto` jitter jumps |
| `LoopUnroll` | 2x loop body duplication with jitter computations |
| `LoopFission` | Multi-statement loop body segmented into phases |
| `IndirectJump` | Sequential blocks converted to indexed dispatch table |
| `RelationalMorph` | Comparison morphing: `a == b` to `(a ^ b) == 0` |
| `LoopToRecursion` | Iterative loops converted to tail-recursive call trees |

### Data Obfuscation & Mathematical Transforms

| Pass | Description |
| :--- | :--- |
| `PolynomialMBA` | Non-linear polynomial + Invertible Affine Layers over Z_2^32 (Anti-Z3) |
| `LinearMBA` | Linear bitwise identities: `x + y` to `(x^y) + 2(x&y)` |
| `FloatMBA` (FLOB) | IEEE-754 lifted into fixed-scale integer MBA domain |
| `EncodeLiterals` | Static string encryption with lazy runtime decryptors |
| `EncodeData` | Variable splitting: scalar `v` into `(v_s1, v_s2)` with `v = v_s1 + v_s2` |
| `LUT` | Arithmetic replaced by 256-element precomputed lookup tables |
| `ArrayInterleave` | Array index wrapping via scaled interleaved stride expressions |
| `StructPermute` | Struct field reordering + random padding injection |
| `PointerMasking` | XOR-masked pointer storage with dereference-site unmasking |
| `HomomorphicEncode` | Scalar domain lift: `x_H = (a·x + b) mod 2^32` |
| `ConstUnfold` | `C` to `(C ^ K) ^ K` constant unfolding |
| `StackAliasing` | Local scalars merged into unified stack frame with S-Box addressing |

### Anti-Analysis & Anti-Debugging

| Pass | Description |
| :--- | :--- |
| `AntiDebug` | `sysctl(KERN_PROC_PID)` / `ptrace PT_DENY_ATTACH` kernel checks |
| `AntiDisasm` | Junk byte prefix injection for linear sweep desynchronization |
| `SelfChecksum` | Runtime CRC32 of function pages to detect `0xCC` breakpoints |
| `TimingCheck` | `mach_absolute_time()` delta anti-stepping detection |
| `HookDetect` | Frida / Substrate / Mach-O interpose prologue verification |
| `EarlyStager` | `__attribute__((constructor(101)))` pre-main security stagers |

### Implicit Flow (Hardware Signal Channels)

| Pass | Description |
| :--- | :--- |
| `ImplicitFlow` (SIGSEGV) | Branches via NULL dereference + `sigsetjmp`/`siglongjmp` |
| `SIGFPEFlow` | Branches via `__fpe_denom == 0` arithmetic fault + `sigsetjmp` |
| `SIGILLFlow` | Branches via illegal opcode trap + `SIGILL` handler |
| `ThreadedFlow` | Branch decisions transmitted across `pthread` thread boundaries |
| `SyscallErrorFlow` | Boolean state via intentionally failing system call error codes |

### Inter-Procedural & Symbol Transforms

| Pass | Description |
| :--- | :--- |
| `Merge` | Independent function pairs merged into `__merged_fn(selector, ...)` |
| `Outline` | Basic block slices extracted to static helper functions |
| `Inline` | Small non-recursive functions inlined at call sites |
| `CallGraphFlatten` | Direct calls replaced by `static void *__indirect_call_table[]` |
| `BogusCallInject` | Dead cross-function calls guarded by opaque predicates |
| `ImportHide` | `dlopen`/`dlsym` CRC32-hash-based API resolution |
| `RenameSymbols` | Homoglyph identifier scrambling |
| `StripDirectives` | `#line` pragma and source path stripping |

### Morphing & Code Quality Transforms

| Pass | Description |
| :--- | :--- |
| `InstrSubst` | Stochastic arithmetic substitution across equivalence classes |
| `GhostCode` | Reversible ring-compensated instruction injection |
| `InstrPermute` | Def-Use dependency graph permutation of independent instructions |
| `AntiSlicing` | Phantom variable dataflow entanglement defeating program slicers |
| `OpcodeEqualize` | Shannon entropy histogram smoothing (Anti-DRLDO) |
| `LiveRangeSplit` | Variable lifetime splitting into phased handover variables |

---

## 🚀 Quick Start

### Build Everything
```bash
dune build
```

### Run Tests
```bash
dune runtest
```

### Run Multi-Target Demo
```bash
dune exec ./bin/main.exe
```

### Build & Run C Examples
```bash
make -C examples CC=../_build/default/bin/ocasorry_cc.exe run
```

### Build 4-VCPU License Demo (Full Pipeline)
```bash
./build_license_demo.sh
```

This script:
1. Synthesizes all 4 Sail + JSON VCPU specs via native DDD `ocasorry-synth`
2. Obfuscates `examples/01_license_keygen.c` with 4-VCPU + 10 protection passes
3. Compiles the native AArch64 binary with `clang -O2`
4. Runs automated test vectors (valid, tampered, default keys)

---

## 🔧 Tools

### `ocasorry-synth` — Native DDD Formal Sail ISA Synthesizer

Synthesizes randomized per-build Sail (`.sail`) and JSON (`.json`) ISA specifications for all 4 VCPU tiers (or 8 VCPU cryptographic cascades) with zero external Python dependencies:

```bash
# Synthesize all 4 VCPU specs into examples/
./_build/default/bin/ocasorry_synth.exe --output-dir examples/ --name vISA_Custom_Arch

# Synthesize 8-VCPU AES/Feistel specs into examples/
./_build/default/bin/ocasorry_synth.exe --vcpu 8vcpu --output-dir examples/

# Synthesize a single VCPU tier
./_build/default/bin/ocasorry_synth.exe --vcpu visa --output-json examples/my_visa.json

# Flags:
#   --vcpu {visa,nested_vm,rolling_vkey,ephemeral,all,8vcpu}
#   --output-dir DIR    Write all spec pairs (*.sail + *.json)
#   --output-json FILE  Single-tier JSON output path
#   --output-sail FILE  Single-tier Sail output path
#   --seed INT          Deterministic random seed
#   --name STR          Custom ISA architecture name
```

### `tools/license_keygen.py` — 4-VCPU License Key Generator

Generates and validates 16-character license keys satisfying the full 4-VCPU cascade:

```bash
# Generate 5 PRO- keys with full VCPU trace
python3 tools/license_keygen.py -n 5 --prefix PRO- --verify

# Validate an existing key
python3 tools/license_keygen.py --check "PRO-9842-KLM9-77"

# Generate Enterprise keys as JSON, save to file
python3 tools/license_keygen.py -n 10 --prefix ENT- --json --output keys.txt
```

> See [docs/license-keygen.md](docs/license-keygen.md) for full documentation including cascade math and solver algorithm.

---

## 📂 Examples

| File | Description |
| :--- | :--- |
| [`examples/01_license_keygen.c`](examples/01_license_keygen.c) | 4-VCPU license key validator — primary obfuscation demo target |
| [`examples/01_keygen_tool.c`](examples/01_keygen_tool.c) | Native C meet-in-the-middle keygen + verifier |
| [`examples/01_license_keygen_obfuscated.c`](examples/01_license_keygen_obfuscated.c) | OcaSorry output: fully obfuscated C source |
| [`examples/01_license_keygen_virtualized.bin`](examples/01_license_keygen_virtualized.bin) | Compiled native AArch64 protected binary |
| [`examples/vcpu1_visa.sail`](examples/vcpu1_visa.sail) | Formal Sail spec — Tier 1 random_vISA Vector ISA |
| [`examples/vcpu2_nested_vm.sail`](examples/vcpu2_nested_vm.sail) | Formal Sail spec — Tier 2 Nested Hierarchical VM |
| [`examples/vcpu3_rolling_vkey.sail`](examples/vcpu3_rolling_vkey.sail) | Formal Sail spec — Tier 3 Stateful Rolling Key VM |
| [`examples/vcpu4_ephemeral_jit.sail`](examples/vcpu4_ephemeral_jit.sail) | Formal Sail spec — Tier 4 Ephemeral JIT Wiper VM |
| [`examples/02_aes_sbox_mini.c`](examples/02_aes_sbox_mini.c) | AES S-Box mini — MBA & LUT obfuscation demo |
| [`examples/03_state_machine_game.c`](examples/03_state_machine_game.c) | State machine game — CFF & BCF obfuscation demo |
| [`examples/04_signal_auth_checker.c`](examples/04_signal_auth_checker.c) | Signal-based auth — implicit flow demo |
| [`examples/05_multi_function_api.c`](examples/05_multi_function_api.c) | Multi-function API — Merge & Outline demo |

---

## 📄 License

MIT License.
