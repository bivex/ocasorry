# Vectis Python ML pipeline targets
.PHONY: ml-verify ml-dataset ml-optimize ml-architect ml-synthesize ml-bridge ml-pipeline

ml-verify:  ## Formally verify all Sail ISA specs (Z3 QFBV)
	@echo "[Vectis] Verifying Sail ISA specs..."
	python3 tools/mlx_neural_sail_verifier.py examples/

ml-dataset:  ## Generate Sail ISA training dataset
	python3 tools/sail_dataset_gen.py -n 500 -o tools/sail_dataset.json

ml-optimize:  ## Optimize ISA params via Deep Ensemble (requires ml-dataset)
	python3 tools/mlx_sail_optimizer.py --dataset tools/sail_dataset.json --vcpu all \
		--output tools/sail_optimal_params.json

ml-architect:  ## Train VCPU profile architect (requires ml-optimize)
	python3 tools/mlx_vcpu_architect.py --retrain

ml-synthesize:  ## RL-synthesize MBA-hardened C11 VCPU kernel
	python3 tools/mlx_neural_vm_synthesizer.py --test

ml-bridge:  ## Feed optimal params back to ocasorry_synth (Gap-1)
	python3 tools/sail_params_to_synth.py --params tools/sail_optimal_params.json

ml-pipeline: ml-dataset ml-optimize ml-architect ml-synthesize ml-bridge ml-verify  ## Full ML pipeline
