#!/usr/bin/env bash
# ==============================================================================
#  OcaSorry - 4-VCPU Federated License Protection & Demo Builder
#  Automates 4-Tier Virtualization, Full-Arsenal Obfuscation, and Verification
# ==============================================================================

set -euo pipefail

# Resolve physical script directory even when executed through a symlink
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="$( cd -P "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd )"

# Colors
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[32m"
C_BLUE="\033[34m"
C_CYAN="\033[36m"
C_YELLOW="\033[33m"
C_MAGENTA="\033[35m"
C_RED="\033[31m"

INPUT_SRC="${ROOT_DIR}/examples/01_license_keygen.c"
OUTPUT_C="${ROOT_DIR}/examples/01_license_keygen_obfuscated.c"
OUTPUT_VIRT_C="${ROOT_DIR}/examples/01_license_keygen_virtualized.c"
OUTPUT_BIN="${ROOT_DIR}/examples/01_license_keygen_virtualized.bin"
OBF_BIN="${ROOT_DIR}/_build/default/bin/main.exe"

# Export OPAM and Homebrew environment if present
export PATH="${HOME}/.opam/default/bin:${PATH}:/opt/homebrew/bin:/usr/local/bin"

echo -e "${C_CYAN}${C_BOLD}"
echo "================================================================="
echo "       OcaSorry: 4-VCPU Federated License Keygen Builder         "
echo "================================================================="
echo -e "${C_RESET}"

# Step 1: Ensure OcaSorry compiler executable is built
if [[ ! -f "${OBF_BIN}" ]]; then
    echo -e "${C_YELLOW}[*] Building OcaSorry compiler toolchain via dune...${C_RESET}"
    (cd "${ROOT_DIR}" && dune build)
    echo -e "${C_GREEN}[+] Dune build complete!${C_RESET}\n"
fi

# Step 2: Obfuscate source code with 4-VCPU Architecture and 27-pass defense arsenal
echo -e "${C_BLUE}[1/3] Applying 4-VCPU Federated Virtualization & Hardening Arsenal...${C_RESET}"
echo -e "${C_MAGENTA}  [4-VCPU Virtualization Cascade]:${C_RESET}"
echo "      ├── Tier 1 (VCPU 1): random_vISA Vector Processor (.vbc opcode words)"
echo "      ├── Tier 2 (VCPU 2): Nested Multi-Layer VM (Outer VM -> Inner VM dispatch)"
echo "      ├── Tier 3 (VCPU 3): Stateful Rolling Key VM (VKey_{n+1} = f(VKey_n, Op_n))"
echo "      └── Tier 4 (VCPU 4): In-Memory Ephemeral JIT VM (mmap -> execute -> zero -> munmap)"
echo -e "${C_MAGENTA}  [Mathematical & Structural Hardening]:${C_RESET}"
echo "      ├── High-Order Polynomial MBA & Affine Rings over Z_2^32 (Anti-Z3)"
echo "      ├── Control Flow Flattening (CFF state machine dispatcher)"
echo "      ├── Invariant & Dynamic Math Opaque Predicates"
echo "      ├── Bogus Control Flow (BCF Cloning & Mutation)"
echo "      ├── String Literal Encryption (EncodeLiterals)"
echo "      ├── Scalar Variable Splitting (EncodeData)"
echo "      ├── 256-Byte Lookup Table Arithmetic (LUT)"
echo "      ├── Array Interleaving & Struct Permutation"
echo "      ├── Homomorphic Data Encoding"
echo "      └── Indirect Jump Tables & Call Graph Flattening"
echo -e "${C_MAGENTA}  [Anti-Analysis, Anti-Debugging & Loader Stagers]:${C_RESET}"
echo "      ├── Anti-Debug Active Termination (sysctl P_TRACED & ptrace PT_DENY_ATTACH)"
echo "      ├── Anti-Disassembly (Junk Byte Desync opcodes)"
echo "      ├── Self-Checksumming (CRC32 Memory Page Hash Guards)"
echo "      ├── Timing Verification (mach_absolute_time delta anti-stepping)"
echo "      ├── Dynamic Hook & Trampoline Detection"
echo "      ├── Dynamic POSIX API Hashing (dlsym CRC32 import hiding)"
echo "      ├── Pre-Main Security Constructor (__attribute__((constructor(101))))"
echo "      ├── Identifier Homoglyph Renaming (_l1I_...)"
echo "      └── Source Directives & #line Stripping"

"${OBF_BIN}" -i "${INPUT_SRC}" -o "${OUTPUT_C}" \
    --virtualize \
    --poly-mba \
    --cff \
    --opaque \
    --dyn-opaque \
    --bcf \
    --literals \
    --split \
    --lut \
    --interleave \
    --permute-struct \
    --homomorphic \
    --unroll \
    --fission \
    --indirect \
    --call-flatten \
    --anti-debug \
    --anti-disasm \
    --self-checksum \
    --timing-check \
    --hook-detect \
    --api-hash \
    --constructor \
    --rename \
    --strip

cp "${OUTPUT_C}" "${OUTPUT_VIRT_C}"
echo -e "\n${C_GREEN}[+] Obfuscated C source generated -> ${OUTPUT_C}${C_RESET}\n"

# Step 3: Compile with Clang & Ad-Hoc Sign on macOS
echo -e "${C_BLUE}[2/3] Compiling native AArch64 binary with clang -O2...${C_RESET}"
clang -w -O2 "${OUTPUT_C}" -o "${OUTPUT_BIN}"

if [[ "$(uname)" == "Darwin" ]] && command -v codesign &>/dev/null; then
    codesign -f -s - "${OUTPUT_BIN}" >/dev/null 2>&1 || true
fi

echo -e "${C_GREEN}[+] Native executable compiled -> ${OUTPUT_BIN}${C_RESET}\n"

# Step 4: Verification test vectors
echo -e "${C_BLUE}[3/3] Running Validation Test Vectors on 4-VCPU Binary...${C_RESET}"

# Test 1: Valid Key
echo -ne "  [Test 1] Valid Key ('PRO-9842-KLM9-77'): "
if "${OUTPUT_BIN}" "PRO-9842-KLM9-77" > /dev/null 2>&1; then
    echo -e "${C_GREEN}${C_BOLD}[PASS: Key Accepted through all 4 VCPUs (Exit 0)]${C_RESET}"
else
    echo -e "${C_RED}${C_BOLD}[FAIL: Valid key was rejected!]${C_RESET}"
    exit 1
fi

# Test 2: Invalid Key
echo -ne "  [Test 2] Invalid Key ('WRONG-KEY-000000'): "
if ! "${OUTPUT_BIN}" "WRONG-KEY-000000" > /dev/null 2>&1; then
    echo -e "${C_GREEN}${C_BOLD}[PASS: Tampered Key Rejected by VCPU Cascade (Exit 1)]${C_RESET}"
else
    echo -e "${C_RED}${C_BOLD}[FAIL: Invalid key was accepted!]${C_RESET}"
    exit 1
fi

# Test 3: Default Key
echo -ne "  [Test 3] Default Key (No arguments): "
if "${OUTPUT_BIN}" > /dev/null 2>&1; then
    echo -e "${C_GREEN}${C_BOLD}[PASS: Default Key Execution Succeeded (Exit 0)]${C_RESET}"
else
    echo -e "${C_RED}${C_BOLD}[FAIL: Default key execution failed!]${C_RESET}"
    exit 1
fi

echo -e "\n${C_GREEN}${C_BOLD}================================================================="
echo "       4-VCPU DEMO BUILD & VERIFICATION COMPLETED!               "
echo -e "=================================================================${C_RESET}"
echo -e "You can run the protected binary directly via:\n  ${C_CYAN}${OUTPUT_BIN} <license_key>${C_RESET}\n"
