#!/usr/bin/env bash
# ==============================================================================
#  Vectis - 8-VCPU Federated AES/Feistel Builder (Without nested_vm)
# ==============================================================================

set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
if [[ -f "${SCRIPT_DIR}/dune-project" ]]; then
  ROOT_DIR="${SCRIPT_DIR}"
else
  ROOT_DIR="$( cd -P "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd )"
fi

# Colors
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[32m"
C_BLUE="\033[34m"
C_CYAN="\033[36m"
C_YELLOW="\033[33m"
C_MAGENTA="\033[35m"
C_RED="\033[31m"

INPUT_SRC="${ROOT_DIR}/examples/02_aes_sbox_mini.c"
OUTPUT_C="${ROOT_DIR}/examples/02_aes_sbox_mini_obfuscated.c"
OUTPUT_BIN="${ROOT_DIR}/examples/02_aes_sbox_mini.bin"
OBF_BIN="${ROOT_DIR}/_build/default/bin/main.exe"
EXAMPLES_DIR="${ROOT_DIR}/examples"

export PATH="${HOME}/.opam/default/bin:${PATH}:/opt/homebrew/bin:/usr/local/bin"

echo -e "${C_CYAN}${C_BOLD}"
echo "================================================================="
echo "       Vectis: 8-VCPU Federated AES Block Cipher Builder       "
echo "                 (Pure 8-VCPU Cascade without nested_vm)         "
echo "================================================================="
echo -e "${C_RESET}"

# Step 1: Ensure Vectis compiler is built
echo -e "${C_YELLOW}[*] Building Vectis compiler toolchain via dune...${C_RESET}"
(cd "${ROOT_DIR}" && dune build)
echo -e "${C_GREEN}[+] Dune build complete!${C_RESET}\n"

# Step 2: Synthesize formal Sail & JSON specifications for all 8 VCPU Tiers
echo -e "${C_BLUE}[1/4] Synthesizing Formal Sail Specifications for all 8 VCPUs via Native DDD Synthesizer...${C_RESET}"
"${ROOT_DIR}/_build/default/bin/vectis_synth.exe" --vcpu 8vcpu --output-dir "${EXAMPLES_DIR}"
echo -e "${C_GREEN}[+] All 8 Sail VCPU Specifications Synthesized successfully!${C_RESET}\n"

# Step 3: Obfuscate source code with 8-VCPU Architecture
echo -e "${C_BLUE}[2/4] Applying 8-VCPU Virtualization with Synthesized ISAs...${C_RESET}"

"${OBF_BIN}" -i "${INPUT_SRC}" -o "${OUTPUT_C}" \
    --visa-spec "${EXAMPLES_DIR}/vcpu1_expand_key.json" \
    --virtualize \
    --rolling-vkey \
    --ephemeral \
    --literals \
    --cff \
    --irreducible-loop \
    --bcf \
    --anti-debug \
    --anti-disasm \
    --timing-check \
    --api-hash \
    --constructor \
    --rename \
    --strip

echo -e "\n${C_GREEN}[+] Obfuscated C source generated -> ${OUTPUT_C}${C_RESET}\n"

# Step 4: Compile with Clang & Ad-Hoc Sign on macOS
echo -e "${C_BLUE}[3/4] Compiling native AArch64 binary with clang -O2...${C_RESET}"
clang -w -O2 -fvisibility=hidden "${OUTPUT_C}" -o "${OUTPUT_BIN}"

# Strip local symbols before signing
strip -x "${OUTPUT_BIN}" 2>/dev/null || true

if [[ "$(uname)" == "Darwin" ]] && command -v codesign &>/dev/null; then
    codesign -f -s - "${OUTPUT_BIN}" >/dev/null 2>&1 || true
fi

echo -e "${C_GREEN}[+] Native executable compiled, stripped & signed -> ${OUTPUT_BIN}${C_RESET}\n"

# Step 5: Verification test vectors
echo -e "${C_BLUE}[4/4] Running 8-VCPU Ciphertext Verification Tests...${C_RESET}"

"${OUTPUT_BIN}"
echo -e "\n${C_GREEN}${C_BOLD}================================================================="
echo "       8-VCPU AES DEMO BUILD & VERIFICATION COMPLETED!           "
echo -e "=================================================================${C_RESET}"
echo -e "You can run the 8-VCPU protected binary directly via:\n  ${C_CYAN}${OUTPUT_BIN} <left_u32> <right_u32>${C_RESET}\n"
