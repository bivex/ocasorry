#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "================================================================="
echo "   Vectis: Native Mach-O 64-Bit E-Graph MBA & VCPU Builder     "
echo "================================================================="

eval $(opam env 2>/dev/null || true)

echo "[1/4] Building Vectis compiler toolchain..."
dune build bin/main.exe bin/vectis_synth.exe

SAIL_OUT="${ROOT_DIR}/examples/optimal_license_sail"
mkdir -p "${SAIL_OUT}"

echo "[2/4] Synthesizing Formal 4-VCPU Sail & JSON Specifications..."
"${ROOT_DIR}/_build/default/bin/vectis_synth.exe" \
  --vcpu all \
  --name "MachO_EGraph_4VCPU_Arch" \
  --output-dir "${SAIL_OUT}"

SRC="${ROOT_DIR}/examples/08_egraph_mba_macho_demo.c"
OBF_SRC="${ROOT_DIR}/examples/08_egraph_mba_macho_demo_virtualized.c"
OUT_BIN="${ROOT_DIR}/examples/08_egraph_mba_macho_demo_virtualized.bin"

echo "[3/4] Obfuscating with E-Graph MBA, Loki, Micro-Dispatcher, Anti-VTIL, 4-VCPU, EH Shadowing..."
"${ROOT_DIR}/_build/default/bin/main.exe" \
  -i "${SRC}" \
  -o "${OBF_SRC}" \
  --visa-spec "${SAIL_OUT}/vcpu1_visa.json" \
  --egraph-mba \
  --egraph-depth 3 \
  --loki-invariants \
  --anti-vtil \
  --eh-shadow \
  --virtualize \
  --nested-vm \
  --rolling-vkey \
  --literals \
  --strip \
  --vm-profile hardened-128k

echo "[4/4] Compiling native macOS Mach-O 64-Bit executable..."
clang -w -O2 -fvisibility=hidden "${OBF_SRC}" -o "${OUT_BIN}"
strip -x "${OUT_BIN}"
codesign -f -s - "${OUT_BIN}" >/dev/null 2>&1 || true

echo ""
echo "=== Mach-O 64-Bit Binary Inspection ==="
file "${OUT_BIN}"
ls -lh "${OUT_BIN}"
echo "Mach-O Header:"
otool -hv "${OUT_BIN}" | head -n 5

echo ""
echo "=== Running Live Mach-O Verification Tests ==="
"${OUT_BIN}" --test

echo ""
echo "================================================================="
echo "  Mach-O E-Graph MBA Demo is Ready:"
echo "  ${OUT_BIN} <key>"
echo "================================================================="
