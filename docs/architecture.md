# Hexagonal Architecture & Domain-Driven Design (DDD)

**OcaSorry** follows Domain-Driven Design and Hexagonal Architecture (Ports and Adapters). The codebase is partitioned into distinct layers ensuring that core obfuscation logic remains 100% decoupled from underlying OS syscalls, third-party libraries, and target hardware platforms.

---

## 🏛️ Layer Overview

```
                                [ Driving Adapters ]
                     (CLI Drivers: bin/main.ml, bin/ocasorry_cc.ml)
                                         │
                                         ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ APPLICATION LAYER (Use Cases)                                                   │
│   • Obfuscate_c_source_usecase  : Source-to-Source pipeline orchestration       │
│   • Jit_runner_usecase          : CFG obfuscation, compilation & execution      │
│   • Two_tier_jit_usecase        : Multi-tier staging & signal router            │
│                                                                                 │
│   ┌──────────────────────────────────────────────────────────────────────────┐  │
│   │ DOMAIN LAYER (Pure Business Logic)                                       │  │
│   │                                                                          │  │
│   │   [ Entities & Value Objects ]                                           │  │
│   │     • Types.reg (X0..X30, SP, XZR)                                       │  │
│   │     • Types.condition (EQ, NE, CS, CC, MI, PL, VS, VC, HI, LS, GE, LT...) │  │
│   │     • Ast.instruction (Add, Sub, Eor, Orr, And, MovImm, B, Bcc, Ret...)  │  │
│   │     • Cfg.BasicBlock, Cfg.CFG                                            │  │
│   │                                                                          │  │
│   │   [ Domain Services - Native IR ]      [ Domain Services - CIL C-AST ]   │  │
│   │     • Mba_service                        • C_mba_service                 │  │
│   │     • Flattening_service                 • C_flattening_service          │  │
│   │     • Opaque_predicate_service           • C_opaque_service              │  │
│   │     • Two_tier_jit_service               • C_encode_literals_service     │  │
│   │                                          • C_encode_data_service         │  │
│   │                                          • C_implicit_flow_service       │  │
│   │                                                                          │  │
│   │   [ Driven Ports (SPI) ]                                                 │  │
│   │     • C_source_port.S   • Encoder_port.S                                 │  │
│   │     • Executor_port.S   • Entropy_port.S                                 │  │
│   └──────────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────┬────────────────────────────────────────┘
                                         │
                                         ▼
                                [ Driven Adapters ]
        • Goblint_cil_adapter       • Aarch64_encoder_adapter
        • Cil_encoder_adapter       • Posix_mmap_adapter (C-FFI)
        • Cil_vm_adapter            • System_entropy_adapter
```

---

## 📂 Layer Details

### 1. Pure Domain Layer (`lib/domain/`)
- **Entities & Value Objects (`types.ml`, `ast.ml`, `cfg.ml`)**: Immutable models representing ARM64 registers, immediates, instruction variants, and basic blocks.
- **Native Services (`services/native/`)**: AST-to-AST transformation algorithms operating purely on `CFG.t` without I/O or side effects.
- **C Source Services (`services/c_source/`)**: CIL AST visitors operating on George Necula's `GoblintCil.Cil.file` representation.
- **Driven Ports (`ports/`)**: Module signatures defining outbound capabilities required by domain services.

### 2. Application Layer (`lib/application/`)
- Encapsulates user tasks into repeatable Use Cases.
- Configures and stitches together transformation passes according to `pipeline_config` and `c_pipeline_config`.

### 3. Infrastructure Layer (`lib/infrastructure/`)
- **Encoders (`encoders/arm64/`, `encoders/cil/`)**: Concrete binary emitters translating intermediate CFGs into byte streams and resolving branch targets.
- **Runtime (`runtime/`)**: Low-level memory managers (`mmap(MAP_JIT)`, cache flush) and stack-machine interpreters.
- **Frontend (`c_frontend/`)**: Parser and pretty-printer adapters wrapping `GoblintCil.Frontc` and `GoblintCil.Cil`.
- **Random (`random/`)**: System entropy source for deterministic or cryptographic seeds.
