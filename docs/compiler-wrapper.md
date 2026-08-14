# Compiler Wrapper (`ocasorry-cc`)

`ocasorry-cc` is a drop-in C compiler wrapper designed to integrate seamlessly into existing build systems (Makefiles, CMake, Meson, Ninja, CI/CD pipelines).

---

## 🚀 Quick Usage

Set `CC=ocasorry-cc` in your build environment:

```bash
# Standard Makefile
CC=ocasorry-cc make

# CMake project
cmake -DCMAKE_C_COMPILER=ocasorry-cc ..
make

# Direct invocation
ocasorry-cc -O2 -c secret_crypto.c -o secret_crypto.o
```

---

## ⚙️ Command-Line Flags

| Flag | Description | Default |
| :--- | :--- | :--- |
| `--ocasorry-disable` | Disables obfuscation (pass-through to underlying compiler) | Off |
| `--ocasorry-no-mba` | Disables Mixed Boolean-Arithmetic | MBA Enabled |
| `--ocasorry-no-cff` | Disables Control Flow Flattening | CFF Enabled |
| `--ocasorry-no-opaque` | Disables Invariant Opaque Predicates | Opaque Enabled |
| `--ocasorry-no-literals` | Disables String Literal Encryption | Literals Enabled |
| `--ocasorry-no-split` | Disables Variable Splitting (`EncodeData`) | Splitting Enabled |
| `--ocasorry-implicit` | Enables Signal-Driven Implicit Flow (`SIGSEGV`) | Off |

---

## 🔧 Environment Variables

- **`OCASORRY_CC`**: Path to the underlying compiler binary (defaults to `clang` on macOS, `gcc` on Linux).
  ```bash
  export OCASORRY_CC=/usr/bin/clang
  ```
- **`OCASORRY_VERBOSE=1`**: Enables verbose debug logging showing transformed temporary files and compiler command lines.
  ```bash
  export OCASORRY_VERBOSE=1
  ```
