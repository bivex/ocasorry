# Vectis ML pipeline — runs OCaml build then full Python AI pipeline
SHELL        := /bin/bash
PYTHON3      := python3
TOOLS        := tools
EXAMPLES     := examples
DATASET      := $(TOOLS)/sail_dataset.json
OPT_PARAMS   := $(TOOLS)/sail_optimal_params.json

# Inline opam env so every recipe inherits the correct PATH / lib dirs
OPAM_ENV     := $(shell opam env 2>/dev/null)

export $(OPAM_ENV)

VECTIS_BIN   := _build/default/bin/main.exe

# Configurable parameters for obfuscation
IN           ?= $(EXAMPLES)/02_aes_sbox_mini.c
OUT          ?= /tmp/vectis_obfuscated.c
BIN          ?= /tmp/vectis_obfuscated.bin
PROFILE      ?= fortress-256k
SPEC         ?= $(EXAMPLES)/ml_optimized/visa.json
SPECS_DIR    ?= $(EXAMPLES)/ml_optimized
PASSES       ?= --virtualize --rolling-vkey --bcf --cff --anti-debug --egraph-mba --anti-vtil

# Full 4-Tier Federated VCPU Virtualization flags
VFLAGS       ?= --virtualize --nested-vm --rolling-vkey --ephemeral --literals --cff --irreducible-loop --bcf --anti-debug --anti-disasm --timing-check --api-hash --constructor --rename --strip

.PHONY: build ml-verify ml-dataset ml-optimize ml-architect ml-synthesize ml-bridge ml-specs ml-pipeline obfuscate compile-obf virtualize help

build:  ## Build OCaml binaries (required before ml-dataset / obfuscation)
	eval $$(opam env) && dune build

virtualize: build ml-specs  ## Full 4-Tier Federated VCPU Virtualization + compilation (Usage: make virtualize IN=file.c BIN=app.bin)
	@echo "======================================================================"
	@echo "  💎 Vectis: 4-Tier Federated VCPU Virtualization Cascade"
	@echo "======================================================================"
	@echo "  Input Source : $(IN)"
	@echo "  Output C     : $(OUT)"
	@echo "  Binary Target: $(BIN)"
	@echo "  vISA Pool    : $(SPECS_DIR) (per-function ISA fragmentation)"
	@echo "  VM Profile   : $(PROFILE)"
	@echo "----------------------------------------------------------------------"
	$(VECTIS_BIN) -i $(IN) -o $(OUT) --visa-specs-dir $(SPECS_DIR) --vm-profile $(PROFILE) $(VFLAGS)
	@echo "[✓] Virtualized C source emitted -> $(OUT)"
	@echo "[*] Compiling with clang -w -O2 -fvisibility=hidden..."
	clang -w -O2 -fvisibility=hidden $(OUT) -o $(BIN)
	@codesign -f -s - $(BIN) 2>/dev/null || true
	@echo "[✓] Virtualized binary compiled successfully -> $(BIN)"
	@echo "======================================================================"

obfuscate: build ml-specs  ## Obfuscate C file with ML-optimized vISA (Usage: make obfuscate IN=file.c OUT=out.c)
	@echo "[Vectis] Obfuscating $(IN) -> $(OUT)"
	@echo "         Profile: [$(PROFILE)] | ISA Pool: [$(SPECS_DIR)]"
	$(VECTIS_BIN) -i $(IN) -o $(OUT) --visa-specs-dir $(SPECS_DIR) --vm-profile $(PROFILE) $(PASSES)
	@echo "[✓] Successfully obfuscated -> $(OUT)"

compile-obf: obfuscate  ## Obfuscate and compile to binary with Clang (Usage: make compile-obf IN=file.c BIN=app.bin)
	@echo "[Vectis] Compiling $(OUT) -> $(BIN) with clang -O2..."
	clang -O2 $(OUT) -o $(BIN)
	@echo "[✓] Executable ready -> $(BIN)"

ml-specs: build  ## Generate all 4 ML-optimized vISA specs to examples/ml_optimized/
	$(PYTHON3) $(TOOLS)/sail_params_to_synth.py --run

ml-verify:  ## Formally verify all Sail ISA specs (Z3 QFBV)
	@echo "[Vectis] Verifying Sail ISA specs..."
	$(PYTHON3) $(TOOLS)/mlx_neural_sail_verifier.py $(EXAMPLES)/

ml-dataset: build  ## Generate Sail ISA training dataset (builds OCaml first)
	eval $$(opam env) && $(PYTHON3) $(TOOLS)/sail_dataset_gen.py -n 500 -o $(DATASET)

ml-optimize:  ## Optimize ISA params via Deep Ensemble (requires ml-dataset)
	$(PYTHON3) $(TOOLS)/mlx_sail_optimizer.py \
		--dataset $(DATASET) --vcpu all --output $(OPT_PARAMS)

ml-architect:  ## Train VCPU profile architect (requires ml-optimize)
	$(PYTHON3) $(TOOLS)/mlx_vcpu_architect.py \
		--retrain --sail-dataset $(DATASET)

ml-synthesize:  ## RL-synthesize MBA-hardened C11 VCPU kernels for all tiers
	$(PYTHON3) $(TOOLS)/mlx_neural_vm_synthesizer.py --test

ml-discriminate: build  ## Measure True Polymorphic Diversity Index (TPDI) via Apple MLX
	$(PYTHON3) $(TOOLS)/mlx_polymorphism_discriminator.py --test

ml-metamorph: build  ## Measure True Metamorphic Diversity Index (MDI) via Apple MLX
	$(PYTHON3) $(TOOLS)/mlx_metamorphism_evaluator.py --test --samples 10


ml-benchmark: build  ## Full Benchmark: TPDI (10 builds) + Formal Z3 Soundness + License Demo
	@echo "======================================================================"
	@echo "  💎 Vectis: Running Complete Polymorphic & Security Benchmark"
	@echo "======================================================================"
	$(PYTHON3) $(TOOLS)/mlx_polymorphism_discriminator.py --test --samples 10
	@echo ""
	@echo "[*] Verifying Sail ISA Formal Soundness (Z3 QFBV)..."
	$(PYTHON3) $(TOOLS)/mlx_neural_sail_verifier.py $(EXAMPLES)/
	@echo ""
	@echo "[*] Verifying 4-Tier Federated License Cascade Demo..."
	$(MAKE) virtualize IN=examples/01_license_keygen.c OUT=examples/01_license_keygen_virtualized.c BIN=examples/01_license_keygen_virtualized.bin
	./examples/01_license_keygen_virtualized.bin PRO-943DY27VA074
	@echo "======================================================================"
	@echo "  🏆 ALL BENCHMARKS & VERIFICATIONS COMPLETED SUCCESSFULLY!"
	@echo "======================================================================"

ml-bridge:  ## Feed optimal params back to ocasorry_synth CLI (Gap-1)
	$(PYTHON3) $(TOOLS)/sail_params_to_synth.py --params $(OPT_PARAMS)

ml-pipeline: ml-dataset ml-optimize ml-architect ml-synthesize ml-bridge ml-specs ml-verify ml-discriminate  ## Full ML pipeline end-to-end


help:  ## Print available Makefile targets
	@echo "======================================================================"
	@echo "  💎 Vectis: Advanced C Obfuscation & Federated Virtualization Engine "
	@echo "======================================================================"
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS=":.*##"}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

