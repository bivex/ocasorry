# Vectis Next Implementation Plan

## 1. Objectives & Guiding Principles

**Vectis Next** elevates the Vectis compiler/virtualization framework from a collection of individual obfuscation passes into an **end-to-end neural-symbolic compiler & VM protection system**.

Key Principles:
1. **Measured Security**: No unsubstantiated "irreversibility" claims. Every security claim is backed by empirical metrics: CFG recovery, symbolic simplification time, dynamic trace analysis, and black-box I/O approximation error.
2. **Formal Soundness**: Neural models are treated strictly as candidate generators, not oracles. All AST/IR rewrites must be verified via equality saturation (E-Graph) or equivalence checking.
3. **Pluggable Architecture**: Clear separation of compiler frontend, canonical IR, rewriter, VM interpreter, crypto/state masking, JIT backend, and SDK tooling.
4. **Non-Destructive Defense**: Microarchitectural anomaly interlocks use silent throttling / controlled error returns rather than destructive behavior.

---

## 2. Component Structure

```
vectis/
├── compiler/
│   ├── frontend/         # CIL AST parser, CFG builder & annotator
│   ├── ir/               # Canonical Vectis IR (typed, SSA/TAC, explicit effects)
│   ├── canonicalizer/    # Canonical IR normalizer & constant folder
│   ├── transformer/      # Morphing, control-flow & data-encoding passes
│   └── virtualizer/      # AST to Vectis ISA bytecode translator
├── neural/
│   ├── feature_extractor/# AST/IR subtree vectorizer & token embeddings
│   ├── rewrite_model/    # Heuristic & Neural candidate generators
│   ├── rewrite_runtime/  # E-Graph equality saturation & rule engine
│   └── verifier/         # SMT / differential / semantic equivalence verifier
├── vm/
│   ├── isa/              # Vectis Next ISA specification (typed operands, flags, metadata)
│   ├── interpreter/      # C11 & OCaml reference direct-threaded execution engines
│   ├── dispatcher/       # Computed gotos, decentralized jump tables, trap handlers
│   ├── scheduler/        # Non-linear VPC state steppers (Linear, NonLinear, Randomized)
│   └── jit/              # Ephemeral JIT (W^X mmap, cache invalidation, fallback)
├── crypto/
│   ├── key_schedule/     # Domain-separated rotating key schedule: K(pc, state, epoch)
│   ├── bytecode_codec/   # Authenticated encrypted bytecode encoder/decoder
│   └── state_masking/    # Algebraic register masking: v_masked = v_logical ^ M(state)
├── sdk/
│   ├── api/              # Python & OCaml programmatic interface
│   ├── config/           # YAML/JSON profile loader & configuration schema
│   └── build/            # Unified CLI (build, protect, verify, benchmark, inspect, disasm)
├── benchmarks/           # Black-box learnability harness & resistance benchmarks
├── tests/                # Unit, integration, differential fuzzing & regression tests
└── docs/                 # Complete architecture, ISA, security model & SDK guides
```

---

## 3. Detailed Phase Breakdown

### Phase 1: Audit & Documentation (Completed)
- Create `docs/current-architecture.md`
- Create `docs/implementation-plan.md`

### Phase 2: Core Vectis Next ISA & Interpreter
- Design `Vectis_isa` specification with 18 core opcodes (MOV, LOAD, STORE, ADD, SUB, XOR, AND, OR, SHL, SHR, ROL, ROR, CMP, SELECT, BRANCH, CALL, RET, JIT_ESC).
- Implement typed operands (Imm, VReg, Mem), virtual flags (ZF, NF, CF, VF), opaque state registers, and versioned headers.
- Implement reference assembler / disassembler for debug & testing.
- Implement reference interpreter with deterministic state validation.

### Phase 3: Neural-Symbolic Rewriter & E-Graph Equality Saturation
- Implement `Vectis_ir` module for canonical expression graphs.
- Implement `Vectis_egraph` equality saturation engine:
  - Equivalence classes (`eclass`)
  - Structural hashing & hashconsing
  - Union-Find with path compression
  - Algebraic rule set (MBA identities, bitwise rewrites, arithmetic equivalences)
  - Cost model (`node_count + depth + non_linearity_penalty`)
  - Bounded memory / iteration limits (preventing infinite saturation).
- Implement `Vectis_neural_rewriter` with:
  - `RewriteCandidate`, `RewriteResult`, `RewriteVerifier`, `RewriteCostModel`
  - Heuristic fallback and ML candidate generator interface
  - SMT/differential equivalence verifier.
- Implement training dataset generator (`tools/neural_dataset_gen.py`).

### Phase 4: Advanced Security & State Hardening
- **Dynamic State Masking**:
  - Virtual registers parameterized as $V_{phys} = V_{log} \oplus \text{Mask}(S_{epoch})$.
  - Mask state transition protocol triggered on VM branch / memory operations.
- **Rotating Bytecode Codec**:
  - Key schedule $K(pc, state, epoch) = \text{BLAKE2s/HMAC}(Domain, pc \parallel state \parallel epoch)$.
  - Integrity tag per instruction block to detect tampering.
- **Nonlinear VPC Stepper**:
  - Pluggable `StateStepper` interface with `LinearStepper`, `NonlinearStepper` (quadratic polynomial $S_{n+1} = (S_n \times G_1 + G_2) \bmod M$), and `RandomizedStepper`.
- **Nested VM Execution**:
  - `ENTER_NESTED_VM` / `EXIT_NESTED_VM` context frame transitions with isolated register namespaces and bounded nesting depth.
- **Ephemeral JIT Backend**:
  - Secure memory management with `MAP_JIT` / W^X, cache invalidation (`sys_icache_invalidate`), and automatic fallback to interpreter on allocation failure.
- **Microarchitectural Telemetry & Interlock**:
  - Passive timing/sampling monitor, policy engine for throttling and controlled failure returns.

### Phase 5: SDK, CLI & Black-Box Behavior Benchmark
- Unified Python SDK (`vectis` package):
  - `vectis.protect()`, `vectis.build()`, `vectis.verify()`, `vectis.benchmark()`.
- Unified CLI:
  - `vectis build`, `vectis protect`, `vectis verify`, `vectis benchmark`, `vectis inspect`, `vectis disasm`.
- Configuration schema supporting YAML/JSON options.
- **Black-Box Behavior Security Benchmark (`benchmarks/blackbox_behavior_benchmark.py`)**:
  - Synthesize controlled input corpora across 5 target function categories (arithmetic, bitwise, CRC, FSM, toy crypto).
  - Train ML surrogate models (Gradient Boosted Trees, MLP, Trace Transformer) to estimate function learnability.
  - Measure exact-match rate, sample complexity, and recovery resistance.

### Phase 6: Verification, Testing & Fuzzing
- Comprehensive unit tests in `test/suites/`.
- Differential fuzzing harness comparing native vs virtualized outputs across edge cases.
- Automated reproducer generator on mismatch (`artifacts/failures/<hash>/`).

### Phase 7: Hardening, Documentation & Final Report
- Comprehensive documentation:
  - `docs/architecture.md`
  - `docs/vm-isa.md`
  - `docs/neural-rewriter.md`
  - `docs/security-model.md`
  - `docs/sdk.md`
  - `docs/build.md`
  - `docs/benchmarks.md`
- Final benchmark validation and test suite execution.
