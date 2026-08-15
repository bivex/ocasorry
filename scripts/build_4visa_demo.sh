#!/usr/bin/env bash
# ==============================================================================
#  Vectis - Interactive 4-vISA Federated Obfuscation & License Demo Builder
# ==============================================================================

set -euo pipefail

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

INPUT_SRC="${ROOT_DIR}/examples/06_4visa_federated_license_demo.c"
OUTPUT_C="${ROOT_DIR}/examples/06_4visa_federated_license_demo_virtualized.c"
OUTPUT_BIN="${ROOT_DIR}/examples/06_4visa_federated_license_demo_virtualized.bin"
OBF_BIN="${ROOT_DIR}/_build/default/bin/main.exe"
SYNTH_BIN="${ROOT_DIR}/_build/default/bin/vectis_synth.exe"
OPTIMAL_SAIL_DIR="${ROOT_DIR}/examples/optimal_license_sail"

export PATH="${HOME}/.opam/default/bin:${PATH}:/opt/homebrew/bin:/usr/local/bin"

echo -e "${C_CYAN}${C_BOLD}"
echo "================================================================="
echo "       Vectis: 4-vISA Federated License Obfuscation Demo       "
echo "================================================================="
echo -e "${C_RESET}"

# Step 1: Dune build toolchain
echo -e "${C_YELLOW}[*] Step 1: Building Vectis compiler toolchain...${C_RESET}"
(cd "${ROOT_DIR}" && eval $(opam env 2>/dev/null || true) && dune build)
echo -e "${C_GREEN}[+] Compiler toolchain ready!${C_RESET}\n"

# Step 2: Synthesize formal Sail ISAs
echo -e "${C_BLUE}[*] Step 2: Synthesizing Formal 4-vISA Specifications (Sail + JSON)...${C_RESET}"
mkdir -p "${OPTIMAL_SAIL_DIR}"
"${SYNTH_BIN}" --vcpu all --output-dir "${OPTIMAL_SAIL_DIR}" --name="LicenseCascade_4vISA"
echo -e "${C_GREEN}[+] Synthesized 4-vISA specs in ${OPTIMAL_SAIL_DIR}${C_RESET}\n"

# Step 3: Obfuscate with 4-vISA Federated Cascade
echo -e "${C_BLUE}[*] Step 3: Obfuscating C Source with 4-vISA Federated Virtualization...${C_RESET}"
"${OBF_BIN}" -i "${INPUT_SRC}" -o "${OUTPUT_C}" \
    --visa-spec "${OPTIMAL_SAIL_DIR}/vcpu1_visa.json" \
    --virtualize \
    --nested-vm \
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
    --strip \
    --vm-profile titan

echo -e "${C_GREEN}[+] Obfuscated 4-vISA C source -> ${OUTPUT_C}${C_RESET}\n"

# Step 4: Compile, Strip, and Ad-Hoc Sign Binary
echo -e "${C_BLUE}[*] Step 4: Compiling native AArch64 executable with clang -O2...${C_RESET}"
clang -w -O2 -fvisibility=hidden "${OUTPUT_C}" -o "${OUTPUT_BIN}"
strip -x "${OUTPUT_BIN}" 2>/dev/null || true

if [[ "$(uname)" == "Darwin" ]] && command -v codesign &>/dev/null; then
    codesign -f -s - "${OUTPUT_BIN}" >/dev/null 2>&1 || true
fi
echo -e "${C_GREEN}[+] 4-vISA protected executable -> ${OUTPUT_BIN}${C_RESET}\n"

# Step 5: Run Verification Test Suite
echo -e "${C_BLUE}[*] Step 5: Running 4-vISA Cascade Test Suite...${C_RESET}"
"${OUTPUT_BIN}" --test

echo -e "\n${C_BLUE}[*] Generating Sample License Keys via Built-in Keygen...${C_RESET}"
"${OUTPUT_BIN}" --gen 3 "PRO-"

echo -e "\n${C_GREEN}${C_BOLD}================================================================="
echo "        4-vISA DEMO COMPLETE & OPERATIONAL!                     "
echo -e "=================================================================${C_RESET}"
echo -e "Run interactive verification with:\n  ${C_CYAN}${OUTPUT_BIN}${C_RESET}\n"
