# 🧬 Code Morphing Engine: Architecture & Implementation Roadmap

This document outlines the completed implementation of the **Code Morphing Engine** in **OcaSorry**, structured across 4 fundamental compiler abstraction levels.

---

## 📊 Morphing Techniques Status Matrix

| Level | Technique | CIL AST Mechanism | Status |
| :--- | :--- | :--- | :---: |
| **1. Instruction Level** | **Instruction Substitution** | Rewrites arithmetic & logic AST expressions into randomized equivalent substitution patterns (`x + 1` $\to$ `-~x`, `x = 0` $\to$ `x = x ^ x`). | `[x]` |
| **1. Instruction Level** | **Ghost / Dead Code (Null-Ring)** | Injects reversible instructions with null-ring algebraic compensation ($\sum \Delta \equiv 0$). | `[x]` |
| **2. Register Level** | **Live Range Splitting** | Slices continuous variable lifetimes into disjoint phase intervals connected by algebraic handover transfers. | `[x]` |
| **3. Control Flow Level** | **Diophantine Opaque Predicates** | Injects unsolvable integer equations ($7x^2 - 1 \neq y^2$) guarding branching. | `[x]` |
| **4. Data Flow Level** | **Constant Unfolding** | Deconstructs static integer literals into polynomial expressions ($C = a_n r^n + \dots + a_0$). | `[x]` |
| **4. Data Flow Level** | **Stack Memory Aliasing** | Places local variables inside a unified stack byte frame accessed via S-Box permutations. | `[x]` |

---

## 🏗️ Implementation Checklist

- [x] `lib/domain/services/c_source/morphing/c_instruction_subst_service.ml` (Suite 45)
- [x] `lib/domain/services/c_source/morphing/c_ghost_code_service.ml` (Suite 46)
- [x] `lib/domain/services/c_source/morphing/c_live_range_split_service.ml` (Suite 47)
- [x] `lib/domain/services/c_source/morphing/c_constant_unfold_service.ml` (Suite 48)
- [x] `lib/domain/services/c_source/morphing/c_stack_aliasing_service.ml` (Suite 49)
- [x] Pipeline integration in `lib/application/obfuscate_c_source_usecase.ml`
- [x] CLI flags in `bin/ocasorry_cc.ml` and `bin/main.ml`
- [x] Test suites: `Suite 45`, `Suite 46`, `Suite 47`, `Suite 48`, `Suite 49`
- [x] Documentation update in `docs/cil-capabilities.md` and `docs/obfuscation-passes.md`
