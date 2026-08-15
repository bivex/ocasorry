#!/usr/bin/env bash
# ==============================================================================
#  OcaSorry - 4-VCPU Federated License Keygen Builder (Sail / Python vISA)
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

INPUT_SRC="${ROOT_DIR}/examples/01_license_keygen.c"
OUTPUT_C="${ROOT_DIR}/examples/01_license_keygen_obfuscated.c"
OUTPUT_VIRT_C="${ROOT_DIR}/examples/01_license_keygen_virtualized.c"
OUTPUT_BIN="${ROOT_DIR}/examples/01_license_keygen_virtualized.bin"
OBF_BIN="${ROOT_DIR}/_build/default/bin/main.exe"
VISA_JSON="${ROOT_DIR}/examples/generated_visa_spec.json"
VISA_SAIL="${ROOT_DIR}/examples/generated_visa_spec.sail"
EXAMPLES_DIR="${ROOT_DIR}/examples"

export PATH="${HOME}/.opam/default/bin:${PATH}:/opt/homebrew/bin:/usr/local/bin"

echo -e "${C_CYAN}${C_BOLD}"
echo "================================================================="
echo "       OcaSorry: 4-VCPU Federated License Keygen Builder         "
echo "================================================================="
echo -e "${C_RESET}"

# Step 1: Ensure OcaSorry compiler executable is built
echo -e "${C_YELLOW}[*] Building OcaSorry compiler toolchain via dune...${C_RESET}"
(cd "${ROOT_DIR}" && dune build)
echo -e "${C_GREEN}[+] Dune build complete!${C_RESET}\n"

# Step 2: Synthesize formal Sail & JSON specifications for all 4 VCPU Tiers
echo -e "${C_BLUE}[1/4] Synthesizing Formal Sail Specifications for all 4 VCPUs...${C_RESET}"
python3 "${ROOT_DIR}/tools/visa_synthesizer.py" --output-dir "${EXAMPLES_DIR}" --name="vISA_License_Cascade_Arch"
echo -e "${C_GREEN}[+] VCPU 1 Sail Spec -> ${EXAMPLES_DIR}/vcpu1_visa.sail${C_RESET}"
echo -e "${C_GREEN}[+] VCPU 2 Sail Spec -> ${EXAMPLES_DIR}/vcpu2_nested_vm.sail${C_RESET}"
echo -e "${C_GREEN}[+] VCPU 3 Sail Spec -> ${EXAMPLES_DIR}/vcpu3_rolling_vkey.sail${C_RESET}"
echo -e "${C_GREEN}[+] VCPU 4 Sail Spec -> ${EXAMPLES_DIR}/vcpu4_ephemeral_jit.sail${C_RESET}\n"

# Step 3: Obfuscate source code with 4-VCPU Architecture and Arsenal Defenses
echo -e "${C_BLUE}[2/4] Applying 4-VCPU Virtualization with Synthesized ISAs...${C_RESET}"

"${OBF_BIN}" -i "${INPUT_SRC}" -o "${OUTPUT_C}" \
    --visa-spec "${EXAMPLES_DIR}/vcpu1_visa.json" \
    --virtualize \
    --nested-vm \
    --rolling-vkey \
    --ephemeral \
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

cp "${OUTPUT_C}" "${OUTPUT_VIRT_C}"
echo -e "\n${C_GREEN}[+] Obfuscated C source generated -> ${OUTPUT_C}${C_RESET}\n"

# Step 4: Compile with Clang & Ad-Hoc Sign on macOS
echo -e "${C_BLUE}[3/4] Compiling native AArch64 binary with clang -O2...${C_RESET}"
clang -w -O2 "${OUTPUT_C}" -o "${OUTPUT_BIN}"

if [[ "$(uname)" == "Darwin" ]] && command -v codesign &>/dev/null; then
    codesign -f -s - "${OUTPUT_BIN}" >/dev/null 2>&1 || true
fi

echo -e "${C_GREEN}[+] Native executable compiled -> ${OUTPUT_BIN}${C_RESET}\n"

# Step 5: Verification test vectors
echo -e "${C_BLUE}[4/4] Running Validation Test Vectors on 4-VCPU Binary...${C_RESET}"

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
