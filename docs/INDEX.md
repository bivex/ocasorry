# 📚 Vectis Next Documentation Index

Welcome to the **Vectis Next** comprehensive technical documentation index.

---

## 🏛️ Core Architecture & Design
- **[System Architecture](architecture.md)** — Hexagonal Domain-Driven Design, Entity boundaries, Ports & Adapters, and the 4-Tier Virtualization cascade.
- **[Current Architecture Audit](current-architecture.md)** — Detailed audit of code structure, CIL AST pipeline, adapters, and MLX neural integration.
- **[Implementation Plan & Roadmap](implementation-plan.md)** — Multi-phase implementation roadmap for Vectis Next.

---

## ⚡ Virtual Machines & Instruction Set
- **[Vectis Virtual ISA v2](vm-isa.md)** — Complete specification of the 18 typed opcodes, condition flags (ZF, NF, CF, VF), algebraic state masking, and non-linear VPC stepping.
- **[4-VCPU Federated Virtualization](4-vcpu-federated-virtualization.md)** — Mathematical modeling of the 4-Tier VCPU cascade (vISA, nested_vm, rolling_vkey, ephemeral_jit).
- **[Virtualization & Random vISA](virtualization-and-random-visa.md)** — Synthetic vector ISA generation, direct-threading dispatch, and self-modifying code.
- **[ISA Generation Pipeline](isa-generation-pipeline.md)** — Formal Sail specification generation and JSON translation into C11 runtime kernels.
- **[Two-Tier JIT & Signals](two-tier-jit.md)** — Dynamic machine code compilation, Apple Silicon W^X cache management, and signal-driven implicit flow.

---

## 🧠 Neural-Symbolic & AI Subsystems
- **[Neural-Symbolic Rewriter & E-Graph](neural-rewriter.md)** — E-Graph equality saturation, sound MBA rewrite rules, neural candidate generation, and SMT equivalence verification.
- **[Apple MLX AI Neural Subsystem](mlx-ai-neural-subsystem.md)** — Apple Silicon Metal GPU acceleration, PPO reinforcement learning for MBA synthesis, and Deep Ensemble optimization.

---

## 🛡️ Security, Cryptography & Licensing
- **[Security Model & Threat Analysis](security-model.md)** — Threat classes (A–D), dynamic algebraic state masking, Anti-Pushan quadratic stepping invariant, and DoD 5220.22-M ephemeral sanitization.
- **[License Keygen & Solver](license-keygen.md)** — 4-VCPU cascade keygen mathematics and meet-in-the-middle suffix solver.
- **[Obfuscation Passes Reference](obfuscation-passes.md)** — Mathematical and theoretical reference for all 61+ CIL and AST protection passes.

---

## 📦 Developer Tools, SDK & Build
- **[SDK & CLI Guide](sdk.md)** — Python SDK (`VectisCompiler`, `VectisConfig`), YAML configuration schema, and unified `vectis` CLI.
- **[Build & Developer Guide](build.md)** — Prerequisites, OCaml 5 + Dune setup, test suite execution, and ML pipeline commands.
- **[Compiler Wrapper](compiler-wrapper.md)** — Drop-in `vectis-cc` wrapper for CMake, Makefiles, and Ninja.
- **[CIL Capabilities Roadmap](cil-capabilities.md)** — Checkbox tracker of all implemented CIL transformations.

---

## 📈 Benchmarks & Empirical Metrics
- **[Benchmarks & Security Metrics](benchmarks.md)** — TPDI Polymorphism Index (Grade A / 75.00), Black-Box Surrogate Resistance (98.88 / 100.0), and 70-suite validation.
