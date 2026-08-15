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

.PHONY: build ml-verify ml-dataset ml-optimize ml-architect ml-synthesize ml-bridge ml-pipeline ml-help

build:  ## Build OCaml binaries (required before ml-dataset)
	eval $$(opam env) && dune build

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

ml-bridge:  ## Feed optimal params back to ocasorry_synth CLI (Gap-1)
	$(PYTHON3) $(TOOLS)/sail_params_to_synth.py --params $(OPT_PARAMS)

ml-pipeline: ml-dataset ml-optimize ml-architect ml-synthesize ml-bridge ml-verify  ## Full ML pipeline end-to-end

ml-help:  ## Print available ML targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS=":.*##"}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
