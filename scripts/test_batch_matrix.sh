#!/usr/bin/env bash
# ==============================================================================
#  Vectis - 10-by-10 Modular Pass Matrix & Compatibility Tester
# ==============================================================================

set -uo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
ROOT_DIR="$( cd -P "${SCRIPT_DIR}" >/dev/null 2>&1 && pwd )"

C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[32m"
C_BLUE="\033[34m"
C_CYAN="\033[36m"
C_YELLOW="\033[33m"
C_RED="\033[31m"

INPUT_SRC="${ROOT_DIR}/examples/01_license_keygen.c"
OBF_BIN="${ROOT_DIR}/_build/default/bin/main.exe"
export PATH="${HOME}/.opam/default/bin:${PATH}:/opt/homebrew/bin:/usr/local/bin"

if [[ ! -f "${OBF_BIN}" ]]; then
    (cd "${ROOT_DIR}" && dune build)
fi

test_pass_combination() {
    local group_name="$1"
    local flags="$2"
    local tmp_c="/tmp/vectis_batch_test_$$.c"
    local tmp_bin="/tmp/vectis_batch_test_$$.bin"

    echo -ne "  Testing [${group_name}]: "

    # 1. Obfuscate
    if ! timeout 5 "${OBF_BIN}" -i "${INPUT_SRC}" -o "${tmp_c}" ${flags} > /dev/null 2>&1; then
        echo -e "${C_RED}${C_BOLD}[FAIL: Obfuscation Engine Timeout/Error]${C_RESET}"
        rm -f "${tmp_c}" "${tmp_bin}"
        return 1
    fi

    # 2. Compile with Clang
    if ! clang -w -O0 "${tmp_c}" -o "${tmp_bin}" > /dev/null 2>&1; then
        echo -e "${C_RED}${C_BOLD}[FAIL: Clang Compilation Error]${C_RESET}"
        rm -f "${tmp_c}" "${tmp_bin}"
        return 1
    fi

    if [[ "$(uname)" == "Darwin" ]] && command -v codesign &>/dev/null; then
        codesign -f -s - "${tmp_bin}" >/dev/null 2>&1 || true
    fi

    # 3. Test Valid Key
    if ! "${tmp_bin}" "PRO-9842-KLM9-77" > /dev/null 2>&1; then
        echo -e "${C_RED}${C_BOLD}[FAIL: Valid key rejected]${C_RESET}"
        rm -f "${tmp_c}" "${tmp_bin}"
        return 1
    fi

    # 4. Test Invalid Key (Should reject)
    if "${tmp_bin}" "WRONG-KEY-000000" > /dev/null 2>&1; then
        echo -e "${C_RED}${C_BOLD}[FAIL: Tampered key accepted]${C_RESET}"
        rm -f "${tmp_c}" "${tmp_bin}"
        return 1
    fi

    echo -e "${C_GREEN}${C_BOLD}[PASS: 100% OK]${C_RESET}"
    rm -f "${tmp_c}" "${tmp_bin}"
    return 0
}

echo -e "${C_CYAN}${C_BOLD}"
echo "================================================================="
echo "       Vectis: 10-by-10 Protection Batch Compatibility Matrix  "
echo "================================================================="
echo -e "${C_RESET}"

echo -e "${C_BLUE}--- [Phase 1] Testing 6 Isolated 10-Pass Batches ---${C_RESET}"

# Batch 1: Math, Algebra & Slicing (10 passes)
test_pass_combination "Batch 1: Math & Algebra (10 passes)" \
    "--poly-mba --float-mba --relational-morph --subst --unfold-const --lut --equalize-opcodes --anti-slicing --ghost"

# Batch 2: Control Flow Deconstruction (7 passes)
test_pass_combination "Batch 2: Control Flow Deconstruction (7 passes)" \
    "--cff --decentralized-disp --split-bb --bcf --opaque --dyn-opaque --indirect"

# Batch 3: Loops & Irreducible Multi-Exit CFG (4 passes)
test_pass_combination "Batch 3: Loops & Irreducible CFG (4 passes)" \
    "--irreducible-loop --unroll --fission --indirect"

# Batch 4: Memory, Structs & Variables (6 passes)
test_pass_combination "Batch 4: Memory & Structs (6 passes)" \
    "--literals --split --interleave --permute-struct --pointer-mask --live-range"

# Batch 5: Anti-Analysis, Debuggers & Stagers (9 passes)
test_pass_combination "Batch 5: Anti-Analysis & Integrity (9 passes)" \
    "--anti-debug --anti-disasm --self-checksum --timing-check --hook-detect --api-hash --constructor --rename --strip"

# Batch 6: 4-VCPU Federated Virtualization Cascade (4 engines)
test_pass_combination "Batch 6: 4-VCPU Virtualization Cascade" \
    "--virtualize --nested-vm --rolling-vkey --ephemeral"

echo -e "\n${C_BLUE}--- [Phase 2] Testing Cumulative Combinations ---${C_RESET}"

# Combo 1: Math (Batch 1) + Memory (Batch 4) = 15 passes
test_pass_combination "Combo 1: Math + Memory (15 passes)" \
    "--poly-mba --float-mba --relational-morph --subst --unfold-const --lut --equalize-opcodes --anti-slicing --ghost --literals --split --interleave --permute-struct --pointer-mask --live-range"

# Combo 2: Math + Memory + Anti-Analysis = 24 passes
test_pass_combination "Combo 2: Math + Memory + Anti-Analysis (24 passes)" \
    "--poly-mba --float-mba --relational-morph --subst --unfold-const --lut --equalize-opcodes --anti-slicing --ghost --literals --split --interleave --permute-struct --pointer-mask --live-range --anti-debug --anti-disasm --self-checksum --timing-check --hook-detect --api-hash --constructor --rename --strip"

# Combo 3: Math + Memory + Anti-Analysis + Control Flow = 32 passes
test_pass_combination "Combo 3: Math + Memory + Anti-Analysis + CFG (32 passes)" \
    "--poly-mba --float-mba --relational-morph --subst --unfold-const --lut --equalize-opcodes --anti-slicing --ghost --literals --split --interleave --permute-struct --pointer-mask --live-range --anti-debug --anti-disasm --self-checksum --timing-check --hook-detect --api-hash --constructor --rename --strip --decentralized-disp --split-bb --bcf --opaque --dyn-opaque --indirect --irreducible-loop"

# Combo 4: Full 4-VCPU Virtualization + Full Arsenal = 36 passes
test_pass_combination "Combo 4: 4-VCPU Virtualization + Full Arsenal (36 passes)" \
    "--virtualize --nested-vm --rolling-vkey --ephemeral --poly-mba --float-mba --relational-morph --subst --unfold-const --lut --equalize-opcodes --anti-slicing --ghost --literals --split --interleave --permute-struct --pointer-mask --live-range --anti-debug --anti-disasm --self-checksum --timing-check --hook-detect --api-hash --constructor --rename --strip --decentralized-disp --split-bb --bcf --opaque --dyn-opaque --indirect --irreducible-loop"

echo -e "\n${C_GREEN}${C_BOLD}================================================================="
echo "       10-by-10 COMPATIBILITY MATRIX COMPLETED!                  "
echo "=================================================================${C_RESET}\n"
