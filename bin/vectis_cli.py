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
    print("[*] Running Vectis Next Black-Box Behavior Benchmark...")
    bench_script = PROJECT_ROOT / "benchmarks/blackbox_behavior_benchmark.py"
    os.system(f"python3 {bench_script}")

def cmd_dataset(args):
    ds_script = PROJECT_ROOT / "tools/neural_dataset_gen.py"
    print(f"[*] Generating neural dataset ({args.count} samples)...")
    os.system(f"python3 {ds_script} -n {args.count} -o {args.output}")

def main():
    parser = argparse.ArgumentParser(prog="vectis", description="Vectis Next Compiler & Security Suite")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # protect
    p_protect = subparsers.add_parser("protect", help="Protect C source code")
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

    # benchmark
    subparsers.add_parser("benchmark", help="Run black-box approximation benchmark")

    # dataset
    p_dataset = subparsers.add_parser("dataset", help="Generate neural training dataset")
    p_dataset.add_argument("-n", "--count", type=int, default=1000, help="Number of samples")
    p_dataset.add_argument("-o", "--output", default="tools/neural_rewrite_dataset.json", help="Output file")

    args = parser.parse_args()

    dispatch = {
        "protect": cmd_protect,
        "build": cmd_build,
        "verify": cmd_verify,
        "benchmark": cmd_benchmark,
        "dataset": cmd_dataset,
    }
    dispatch[args.command](args)

if __name__ == "__main__":
    main()
