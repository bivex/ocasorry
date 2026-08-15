#!/usr/bin/env bash
# ==============================================================================
#  Vectis - 4-VCPU Federated License Keygen Builder (MLX Optimal Sail ISA)
# ==============================================================================

set -euo pipefail

# Resolve real script path through symlinks
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
SYNTH_BIN="${ROOT_DIR}/_build/default/bin/vectis_synth.exe"
EXAMPLES_DIR="${ROOT_DIR}/examples"
OPTIMAL_SAIL_DIR="${EXAMPLES_DIR}/optimal_license_sail"

export PATH="${HOME}/.opam/default/bin:${PATH}:/opt/homebrew/bin:/usr/local/bin"

echo -e "${C_CYAN}${C_BOLD}"
echo "================================================================="
echo "  Vectis: MLX-Optimized 4-VCPU Federated License Builder       "
echo "================================================================="
echo -e "${C_RESET}"

# Step 1: Ensure Vectis compiler & synthesizer executables are built
echo -e "${C_YELLOW}[*] Building Vectis OCaml compiler toolchain via dune...${C_RESET}"
(cd "${ROOT_DIR}" && eval $(opam env 2>/dev/null || true) && dune build)
echo -e "${C_GREEN}[+] Dune build complete!${C_RESET}\n"

# Step 2: Query MLX Neural Policy Network for optimal VCPU profile
echo -e "${C_BLUE}[1/5] Querying MLX Neural VCPU Architect on Apple Silicon GPU...${C_RESET}"
python3 "${ROOT_DIR}/tools/mlx_vcpu_architect.py" \
    --target-size 1024 \
    --threat 4 \
    --complexity 8.5 \
    --ast-nodes 400 \
    --loops 8 \
    --export-json "${EXAMPLES_DIR}/license_optimal_spec.json"

# Step 3: Synthesize optimal formal Sail & JSON specifications for all 4 VCPUs
echo -e "${C_BLUE}[2/5] Synthesizing Formal Polymorphic Sail Specifications via Vectis Synth...${C_RESET}"
mkdir -p "${OPTIMAL_SAIL_DIR}"
"${SYNTH_BIN}" --vcpu all --output-dir "${OPTIMAL_SAIL_DIR}" --name="LicenseCascade_Optimal"

echo -e "${C_GREEN}[+] VCPU 1 Sail Spec -> ${OPTIMAL_SAIL_DIR}/vcpu1_visa.sail${C_RESET}"
echo -e "${C_GREEN}[+] VCPU 2 Sail Spec -> ${OPTIMAL_SAIL_DIR}/vcpu2_nested_vm.sail${C_RESET}"
echo -e "${C_GREEN}[+] VCPU 3 Sail Spec -> ${OPTIMAL_SAIL_DIR}/vcpu3_rolling_vkey.sail${C_RESET}"
echo -e "${C_GREEN}[+] VCPU 4 Sail Spec -> ${OPTIMAL_SAIL_DIR}/vcpu4_ephemeral_jit.sail${C_RESET}\n"

# Step 4: Obfuscate source code with 4-VCPU Architecture and Synthesized ISAs
echo -e "${C_BLUE}[3/5] Applying 4-VCPU Virtualization with Synthesized ISAs & Hardening...${C_RESET}"

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
    --vm-profile colossus

cp "${OUTPUT_C}" "${OUTPUT_VIRT_C}"
echo -e "\n${C_GREEN}[+] Obfuscated C source generated -> ${OUTPUT_C}${C_RESET}\n"

# Step 5: Compile with Clang & Ad-Hoc Sign on macOS
echo -e "${C_BLUE}[4/5] Compiling native AArch64 binary with clang -O2...${C_RESET}"
clang -w -O2 -fvisibility=hidden "${OUTPUT_C}" -o "${OUTPUT_BIN}"
strip -x "${OUTPUT_BIN}" 2>/dev/null || true

if [[ "$(uname)" == "Darwin" ]] && command -v codesign &>/dev/null; then
    codesign -f -s - "${OUTPUT_BIN}" >/dev/null 2>&1 || true
fi

echo -e "${C_GREEN}[+] Native executable compiled, stripped & signed -> ${OUTPUT_BIN}${C_RESET}\n"

# Step 6: Generate dynamic real-time key and run test vectors
echo -e "${C_BLUE}[5/5] Generating Dynamic License Keys & Running Verification...${C_RESET}"

DYNAMIC_KEY=$(python3 "${ROOT_DIR}/tools/license_keygen.py" -n 1 -p "ENT-" | grep "ENT-" | awk '{print $2}')
echo -e "  Generated Fresh Key: ${C_MAGENTA}${C_BOLD}${DYNAMIC_KEY}${C_RESET}"

# Test 1: Freshly Generated Dynamic Key
echo -ne "  [Test 1] Fresh Dynamic Key ('${DYNAMIC_KEY}'): "
if "${OUTPUT_BIN}" "${DYNAMIC_KEY}" > /dev/null 2>&1; then
    echo -e "${C_GREEN}${C_BOLD}[PASS: Key Accepted by 4-VCPU Cascade (Exit 0)]${C_RESET}"
else
    echo -e "${C_RED}${C_BOLD}[FAIL: Valid dynamic key was rejected!]${C_RESET}"
    exit 1
fi

# Test 2: Standard Static Test Key
echo -ne "  [Test 2] Static Golden Key ('PRO-9842-KLM9-77'): "
if "${OUTPUT_BIN}" "PRO-9842-KLM9-77" > /dev/null 2>&1; then
    echo -e "${C_GREEN}${C_BOLD}[PASS: Key Accepted by 4-VCPU Cascade (Exit 0)]${C_RESET}"
else
    echo -e "${C_RED}${C_BOLD}[FAIL: Valid static key was rejected!]${C_RESET}"
    exit 1
fi

# Test 3: Tampered Key (Anti-Tamper & Security Verification)
echo -ne "  [Test 3] Tampered Key ('WRONG-KEY-000000'): "
if ! "${OUTPUT_BIN}" "WRONG-KEY-000000" > /dev/null 2>&1; then
    echo -e "${C_GREEN}${C_BOLD}[PASS: Tampered Key Blocked by Cascade (Exit 1)]${C_RESET}"
else
    echo -e "${C_RED}${C_BOLD}[FAIL: Invalid key was accepted!]${C_RESET}"
    exit 1
fi

echo -e "\n${C_GREEN}${C_BOLD}================================================================="
echo "  4-VCPU MLX-OPTIMIZED DEMO BUILD & VERIFICATION COMPLETED!      "
echo -e "=================================================================${C_RESET}"
echo -e "Protected binary ready at:\n  ${C_CYAN}${OUTPUT_BIN} <license_key>${C_RESET}\n"
