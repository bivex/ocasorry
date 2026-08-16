# 📦 Vectis Next SDK & CLI User Guide

The **Vectis Next SDK** provides high-level programmatic interfaces (Python & OCaml) and a unified CLI for compilation, virtualization, and security auditing.

---

## 🐍 1. Python SDK

### Installation & Quick Start

```python
from tools.vectis_sdk import VectisCompiler, VectisConfig

# Configure virtualization passes
config = VectisConfig(
    virtualize=True,
    poly_mba=True,
    opaque=True,
    dyn_opaque=True,
    rolling_vkey=True,
    vcpu_scramble=True
)

compiler = VectisCompiler(config)

# 1. Protect C source code
compiler.protect_c("src/input.c", "dist/protected.c")

# 2. Build protected native binary directly
compiler.build_binary("src/input.c", "dist/app.bin", clang_opt="-O2")
```

---

## ⚙️ 2. YAML Configuration Schema

Save configuration as `vectis_config.yaml`:

```yaml
virtualize: true
poly_mba: true
opaque: true
dyn_opaque: true
rolling_vkey: true
vcpu_scramble: true
nested_vm: false
ephemeral_payload: false
state_stepper: "nonlinear"
target_arch: "visa_v2"
extra_flags:
  - "--gf-poly"
  - "0x11D"
```

---

## 💻 3. Unified Command-Line Interface (`bin/vectis_cli.py`)

### Commands

| Command | Usage | Description |
|---|---|---|
| `protect` | `vectis protect -i src.c -o out.c [-c config.yaml]` | Virtualizes and hardens C source file |
| `build` | `vectis build -i src.c -o app.bin [-c config.yaml]` | End-to-end builds protected native binary |
| `verify` | `vectis verify [-d examples/]` | Formally verifies Sail ISA specs via Z3 |
| `benchmark` | `vectis benchmark` | Runs black-box surrogate model benchmark |
| `dataset` | `vectis dataset -n 1000 -o dataset.json` | Synthesizes neural rewriter dataset |
