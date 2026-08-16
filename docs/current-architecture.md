# Vectis Current Architecture Audit (Phase 1)

## 1. Overview & Technology Stack

Vectis is an advanced C source obfuscation, virtualization compiler, and multi-tier JIT execution framework written in **OCaml 5.x** with a high-performance **C11 runtime**, **Apple MLX (Metal GPU)** neural optimization ecosystem, and **Goblint-CIL** C frontend.

| Layer | Technology | Primary Purpose |
|---|---|---|
| **Frontend** | Goblint-CIL (CIL AST) | C parsing, type elaboration, CFG synthesis, AST visitors |
| **Domain Logic** | OCaml 5 (DDD / Hexagonal) | 61+ transformation passes, 4-tier VCPU cascade, E-Graph MBA |
| **Virtualization** | C11 Direct-Threaded / Sail ISA | Custom vISA bytecode, Ephemeral JIT escapes, Rolling keys |
| **Neural Subsystem** | Python 3 + Apple MLX / Z3 | PPO VM synthesis, Deep Ensemble ISA optimization, TPDI discriminator |
| **Native Backends** | AArch64 (Apple Silicon) / ECMA-335 CIL | JIT code generation with W^X mmap and cache invalidation |

---

## 2. Component Inventory

```
ocasorry/
├── bin/
│   ├── main.ml               # CLI: standalone multi-pass compiler & JIT demo
│   ├── vectis_cc.ml          # Transparent clang/gcc wrapper for drop-in builds
│   └── vectis_synth.ml       # Synthesis CLI for formal Sail ISA specifications
├── lib/
│   ├── domain/
│   │   ├── services/
│   │   │   ├── c_source/     # 60+ CIL AST passes (MBA, CFF, Opaque, Virtualize)
│   │   │   │   ├── virtualization/
│   │   │   │   │   ├── specs/        # vISA specification, Sail templates, profiles
│   │   │   │   │   ├── compiler/     # CIL AST to vISA bytecode compilers
│   │   │   │   │   ├── emitter/      # C11 runtime, dispatch table, MBA handlers
│   │   │   │   │   ├── hardening/    # VPC invalidation, decentralized dispatch
│   │   │   │   │   └── tiers/        # Ephemeral JIT, nested VM, rolling vkey
│   │   │   │   ├── data_encoding/    # E-Graph MBA (Scrambler), literal/data encryption
│   │   │   │   ├── control_flow/     # Control flow flattening, bogus CFG, opaque preds
│   │   │   │   ├── anti_analysis/    # Anti-debug, anti-VTIL, timing telemetry
│   │   │   │   └── morphing/         # Instruction substitution, relational morphing
│   │   │   └── native/       # Native AArch64 CFG transformations
│   │   └── types.ml, ast.ml, cfg.ml  # Domain models for registers, instructions, CFGs
│   ├── application/          # Use cases: Obfuscate_c_source, Jit_runner, Two_tier_jit
│   └── infrastructure/       # Encoders, Posix mmap (JIT stubs), CIL frontend adapters
├── tools/
│   ├── mlx_polymorphism_discriminator.py # MLX TPDI neural discriminator (Grade A)
│   ├── mlx_neural_vm_synthesizer.py      # PPO RL synthesizer for MBA handlers
│   ├── mlx_sail_optimizer.py             # Deep ensemble ISA parameter optimizer
│   ├── mlx_vcpu_architect.py             # Multi-layer VCPU profile architect
│   └── sail_dataset_gen.py               # Synthetic & formal ISA dataset generator
├── test/
│   └── suites/               # 66 comprehensive unit & regression test suites
└── docs/                     # Architectural specifications & whitepapers
```

---

## 3. Virtualization & Multi-VCPU Cascade

The existing virtualization pipeline implements a 4-tier federated cascade:
1. **Tier 0: Random vISA (`c_virtualize_service.ml`)**:
   Direct-threaded GNU C computed-goto dispatch table, randomized register rotation, and 256-slot synthetic trap S-Boxes.
2. **Tier 1: Nested VM (`c_nested_vm_service.ml`)**:
   Secondary interpreter execution context with independent virtual stack and hash-chained dispatch.
3. **Tier 2: Rolling VKey (`c_rolling_vkey_service.ml`)**:
   Key derivation per VPC step: $K(pc) = K_0 \oplus (pc \times K_1)$, self-scrubbing bytecode scratchpad.
4. **Tier 3: Ephemeral JIT (`c_arm64_jit_compiler.ml`)**:
   Dynamic in-VM AArch64 code generation in ephemeral `mmap(MAP_JIT)` pages with DoD 5220.22-M 3-pass memory sanitization.

---

## 4. Current Limitations & Areas for Next-Gen Upgrades

1. **Static E-Graph Extensibility**: The existing E-graph implementation in `c_egraph_mba_service.ml` is tailored specifically for expanding MBA, but does not provide a general-purpose intermediate representation (IR) rewrite/simplification pipeline for arbitrary expression optimization.
2. **Neural Candidate Verification**: The Python ML tools operate offline or as separate tools; they need a unified Python SDK and standardized candidate-verification feedback loop.
3. **Dynamic State Masking**: Virtual registers in the C VM runtime currently use a linear rotation and XOR mask; an explicit algebraic state-dependent masking system with non-linear stepper is needed.
4. **Black-Box Empirical Security Harness**: We need an automated benchmark suite measuring empirical I/O learnability and function approximation resistance.
5. **Unified CLI & SDK**: Consolidate Python and native tools under a single `vectis` SDK command interface with YAML configuration support.
