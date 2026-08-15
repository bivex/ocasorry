# Compiler Wrapper (`vectis-cc`)

`vectis-cc` is a drop-in C compiler wrapper designed to integrate seamlessly into existing build systems (Makefiles, CMake, Meson, Ninja, CI/CD pipelines).

---

## 🚀 Quick Usage

Set `CC=vectis-cc` in your build environment:

```bash
# Standard Makefile
CC=vectis-cc make

# CMake project
cmake -DCMAKE_C_COMPILER=vectis-cc ..
make

# Direct invocation
vectis-cc -O2 -c secret_crypto.c -o secret_crypto.o
```

---

## ⚙️ Command-Line Flags

| Flag | Description | Default |
| :--- | :--- | :--- |
| `--vectis-disable` | Disables obfuscation (pass-through to underlying compiler) | Off |
| `--vectis-no-mba` | Disables Mixed Boolean-Arithmetic | MBA Enabled |
| `--vectis-no-cff` | Disables Control Flow Flattening | CFF Enabled |
| `--vectis-no-opaque` | Disables Invariant Opaque Predicates | Opaque Enabled |
| `--vectis-no-literals` | Disables String Literal Encryption | Literals Enabled |
| `--vectis-no-split` | Disables Variable Splitting (`EncodeData`) | Splitting Enabled |
| `--vectis-implicit` | Enables Signal-Driven Implicit Flow (`SIGSEGV`) | Off |

---

## 🔧 Environment Variables

- **`VECTIS_CC`**: Path to the underlying compiler binary (defaults to `clang` on macOS, `gcc` on Linux).
  ```bash
  export VECTIS_CC=/usr/bin/clang
  ```
- **`VECTIS_VERBOSE=1`**: Enables verbose debug logging showing transformed temporary files and compiler command lines.
  ```bash
  export VECTIS_VERBOSE=1
  ```
