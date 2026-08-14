#!/usr/bin/env bash
# ==============================================================================
#  OcaSorry - License Keygen Demo Builder
#  Automates building, full-arsenal obfuscation, compilation, and testing
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
echo "       OcaSorry License Keygen Protection & Demo Builder         "
echo "================================================================="
echo -e "${C_RESET}"

# Step 1: Ensure OcaSorry executable is built
if [[ ! -f "${OBF_BIN}" ]]; then
    echo -e "${C_YELLOW}[*] Building OcaSorry compiler toolchain via dune...${C_RESET}"
    (cd "${ROOT_DIR}" && dune build)
    echo -e "${C_GREEN}[+] Dune build complete!${C_RESET}\n"
fi

# Step 2: Obfuscate source code with all 27 protection layers
echo -e "${C_BLUE}[1/3] Obfuscating '${INPUT_SRC}' with Full Protection Arsenal (27 Passes)...${C_RESET}"
echo "      - random_vISA Vector VCPU Virtualization"
echo "      - High-Order Polynomial MBA & Affine Rings (Anti-Z3)"
echo "      - Control Flow Flattening (CFF)"
echo "      - Invariant & Dynamic Math Opaque Predicates"
echo "      - Bogus Control Flow (BCF Cloning & Mutation)"
echo "      - String Literal Encryption (EncodeLiterals)"
echo "      - Scalar Variable Splitting (EncodeData)"
echo "      - 256-Byte Lookup Table Arithmetic (LUT)"
echo "      - Array Interleaving & Folding"
echo "      - Struct Permutation & Padding"
echo "      - Homomorphic Data Encoding"
echo "      - Loop Unrolling & Fission"
echo "      - Indirect Jump Tables & Call Graph Flattening"
echo "      - Anti-Debug Inspection (sysctl P_TRACED & PT_DENY_ATTACH)"
echo "      - Anti-Disassembly (Junk Byte Desync)"
echo "      - Self-Checksumming (CRC32 Hash Guards)"
echo "      - Timing Verification (Anti-Stepping Delta)"
echo "      - Dynamic Hook & Trampoline Detection"
echo "      - Dynamic POSIX API Hashing (dlsym Import Hiding)"
echo "      - Pre-Main Security Constructor (__attribute__((constructor)))"
echo '      - Stateful Rolling Bytecode Key Chain (VKey_{n+1} = f(VKey_n, Op_n))'
echo "      - Polymorphic VCPU Context & Struct Scrambling"
echo "      - In-Memory Ephemeral Payload Unpacking (mmap / munmap zeroing)"
echo "      - Identifier Homoglyph Renaming (_l1I_...)"
echo "      - Source Directives & #line Stripping"

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
echo -e "${C_GREEN}[+] Obfuscated C source generated -> ${OUTPUT_C}${C_RESET}\n"

# Step 3: Compile with Clang & Ad-Hoc Sign on macOS
echo -e "${C_BLUE}[2/3] Compiling native AArch64 binary with clang -O2...${C_RESET}"
clang -w -O2 "${OUTPUT_C}" -o "${OUTPUT_BIN}"

if [[ "$(uname)" == "Darwin" ]] && command -v codesign &>/dev/null; then
    codesign -f -s - "${OUTPUT_BIN}" >/dev/null 2>&1 || true
fi

echo -e "${C_GREEN}[+] Native executable compiled -> ${OUTPUT_BIN}${C_RESET}\n"

# Step 4: Verification test vectors
echo -e "${C_BLUE}[3/3] Running Validation Test Vectors...${C_RESET}"

# Test 1: Valid Key
echo -ne "  [Test 1] Valid Key ('PRO-9842-KLM9-77'): "
if "${OUTPUT_BIN}" "PRO-9842-KLM9-77" > /dev/null 2>&1; then
    echo -e "${C_GREEN}${C_BOLD}[PASS: Key Accepted (Exit code 0)]${C_RESET}"
else
    echo -e "${C_RED}${C_BOLD}[FAIL: Valid key was rejected!]${C_RESET}"
    exit 1
fi

# Test 2: Invalid Key
echo -ne "  [Test 2] Invalid Key ('WRONG-KEY-000000'): "
if ! "${OUTPUT_BIN}" "WRONG-KEY-000000" > /dev/null 2>&1; then
    echo -e "${C_GREEN}${C_BOLD}[PASS: Tampered Key Rejected (Exit code 1)]${C_RESET}"
else
    echo -e "${C_RED}${C_BOLD}[FAIL: Invalid key was accepted!]${C_RESET}"
    exit 1
fi

# Test 3: Default Key
echo -ne "  [Test 3] Default Key (No arguments): "
if "${OUTPUT_BIN}" > /dev/null 2>&1; then
    echo -e "${C_GREEN}${C_BOLD}[PASS: Default Key Accepted (Exit code 0)]${C_RESET}"
else
    echo -e "${C_RED}${C_BOLD}[FAIL: Default key execution failed!]${C_RESET}"
    exit 1
fi

echo -e "\n${C_GREEN}${C_BOLD}================================================================="
echo "       DEMO BUILD & VERIFICATION COMPLETED SUCCESSFULLY!         "
echo -e "=================================================================${C_RESET}"
echo -e "You can run the binary directly via:\n  ${C_CYAN}${OUTPUT_BIN} <license_key>${C_RESET}\n"
