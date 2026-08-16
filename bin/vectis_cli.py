#!/usr/bin/env python3
"""
bin/vectis_cli.py — Unified Vectis Next Command-Line Interface

Commands:
  protect    - Transform and virtualize C source files
  build      - End-to-end compilation to protected native binary
  verify     - Formal Sail ISA specification verification via Z3
  benchmark  - Execute empirical black-box resistance benchmark
  dataset    - Generate neural rewriter training dataset
"""

import sys
import os
import argparse
from pathlib import Path

# Add project root to sys.path
PROJECT_ROOT = Path(__file__).parent.parent.resolve()
sys.path.insert(0, str(PROJECT_ROOT))

from tools.vectis_sdk import VectisCompiler, VectisConfig

def cmd_protect(args):
    config = VectisConfig.from_yaml(args.config) if args.config else VectisConfig()
    compiler = VectisCompiler(config)
    print(f"[*] Protecting {args.input} -> {args.output}...")
    compiler.protect_c(args.input, args.output)
    print(f"[✓] Obfuscated source generated: {args.output}")

def cmd_build(args):
    config = VectisConfig.from_yaml(args.config) if args.config else VectisConfig()
    compiler = VectisCompiler(config)
    print(f"[*] Building protected binary {args.input} -> {args.output}...")
    compiler.build_binary(args.input, args.output, clang_opt=args.opt)
    print(f"[✓] Native binary compiled: {args.output}")

def cmd_verify(args):
    verifier_script = PROJECT_ROOT / "tools/mlx_neural_sail_verifier.py"
    target_dir = args.dir or (PROJECT_ROOT / "examples")
    print(f"[*] Verifying Sail ISA specifications in {target_dir}...")
    os.system(f"python3 {verifier_script} {target_dir}")

def cmd_benchmark(args):
    target = getattr(args, "type", "all")
    # Optional iteration count passthrough (statistical N-repeats)
    iters = getattr(args, "iterations", None)
    iter_flag = f" --iterations {iters}" if iters else ""
    if target in ("all", "smt"):
        print("[*] Running Vectis SMT & Symbolic Execution Hardness Benchmark...")
        os.system(f"python3 {PROJECT_ROOT / 'benchmarks/symbolic_execution_benchmark.py'}")
    if target in ("all", "mba"):
        print("[*] Running Vectis MBA Simplification Benchmark...")
        os.system(f"python3 {PROJECT_ROOT / 'benchmarks/mba_simplification_benchmark.py'}")
    if target in ("all", "diff"):
        print("[*] Running Vectis Binary Diffing & CFG Alignment Benchmark...")
        os.system(f"python3 {PROJECT_ROOT / 'benchmarks/binary_diffing_benchmark.py'}{iter_flag}")
    if target in ("all", "poly"):
        print("[*] Running Vectis Semantic Handler Polymorphism Spike...")
        os.system(f"python3 {PROJECT_ROOT / 'benchmarks/semantic_polymorphism_benchmark.py'}")
    if target in ("all", "trace"):
        print("[*] Running Vectis Dynamic Trace-Lifter & De-virtualization Benchmark...")
        os.system(f"python3 {PROJECT_ROOT / 'benchmarks/trace_lifter_benchmark.py'}")
    if target in ("all", "jit"):
        print("[*] Running Vectis Ephemeral Native Trace JIT Benchmark...")
        os.system(f"python3 {PROJECT_ROOT / 'benchmarks/ephemeral_jit_benchmark.py'}")
    if target in ("all", "concolic"):
        print("[*] Running Vectis Anti-Concolic Path Explosion Benchmark...")
        os.system(f"python3 {PROJECT_ROOT / 'benchmarks/anti_concolic_benchmark.py'}")




def cmd_proof(args):
    cert_tool = PROJECT_ROOT / "tools/vectis_proof_certificate.py"
    if args.action == "generate":
        out = args.output or "examples/proof_certificate.smt2"
        func = args.func or "compute_hot_loop"
        os.system(f"python3 {cert_tool} generate --output {out} --func {func}")
    elif args.action == "verify":
        cert = args.cert or "examples/proof_certificate.smt2"
        os.system(f"python3 {cert_tool} verify --cert {cert}")

def cmd_dataset(args):
    ds_script = PROJECT_ROOT / "tools/neural_dataset_gen.py"

    print(f"[*] Generating neural dataset ({args.count} samples)...")
    os.system(f"python3 {ds_script} -n {args.count} -o {args.output}")

def main():
    parser = argparse.ArgumentParser(
        description="Vectis — 4-VCPU Federated Virtualization & Hardened C Source Obfuscator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # protect
    p_protect = subparsers.add_parser("protect", help="Protect C source file via multi-pass pipeline")
    p_protect.add_argument("-i", "--input", required=True, help="Input C file")
    p_protect.add_argument("-o", "--output", required=True, help="Output C file")
    p_protect.add_argument("-c", "--config", help="Optional YAML configuration file")

    # build
    p_build = subparsers.add_parser("build", help="Build protected native executable")
    p_build.add_argument("-i", "--input", required=True, help="Input C file")
    p_build.add_argument("-o", "--output", required=True, help="Output binary file")
    p_build.add_argument("-c", "--config", help="Optional YAML configuration file")
    p_build.add_argument("--opt", default="-O2", help="Clang optimization level")

    # verify
    p_verify = subparsers.add_parser("verify", help="Verify Sail ISA specifications")
    p_verify.add_argument("-d", "--dir", help="Directory containing Sail specs")

    # proof (Vector 4)
    p_proof = subparsers.add_parser("proof", help="Generate or verify formal SMT-LIB2 equivalence certificates")
    p_proof.add_argument("action", choices=["generate", "verify"], help="Certificate action")
    p_proof.add_argument("-f", "--func", default="compute_hot_loop", help="Target function symbol")
    p_proof.add_argument("-o", "--output", default="examples/proof_certificate.smt2", help="Output .smt2 path")
    p_proof.add_argument("-c", "--cert", default="examples/proof_certificate.smt2", help="Certificate .smt2 path to verify")

    # benchmark
    p_bench = subparsers.add_parser("benchmark", help="Run adversarial deobfuscation benchmarks")
    p_bench.add_argument("--type", choices=["all", "smt", "mba", "diff", "poly", "trace", "jit", "concolic"], default="all", help="Benchmark class to execute")
    p_bench.add_argument("--iterations", type=int, default=None, help="Statistical repeats for the diffing benchmark (default: 20)")

    # dataset
    p_dataset = subparsers.add_parser("dataset", help="Generate neural training dataset")
    p_dataset.add_argument("-n", "--count", type=int, default=1000, help="Number of samples")
    p_indexed = p_dataset.add_argument("-o", "--output", default="tools/neural_rewrite_dataset.json", help="Output file")

    args = parser.parse_args()

    dispatch = {
        "protect": cmd_protect,
        "build": cmd_build,
        "verify": cmd_verify,
        "proof": cmd_proof,
        "benchmark": cmd_benchmark,
        "dataset": cmd_dataset,
    }

    if args.command in dispatch:
        dispatch[args.command](args)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
