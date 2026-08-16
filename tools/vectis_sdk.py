"""
tools/vectis_sdk.py — Vectis Next Python SDK

Provides a high-level programmatic interface to the Vectis compilation,
virtualization, equality saturation, and security benchmark pipeline.
"""

import os
import subprocess
import json
import yaml
from pathlib import Path
from typing import Dict, Any, Optional, List

PROJECT_ROOT = Path(__file__).parent.parent.resolve()
VECTIS_MAIN  = PROJECT_ROOT / "_build/default/bin/main.exe"
VECTIS_CC    = PROJECT_ROOT / "_build/default/bin/vectis_cc.exe"

class VectisConfig:
    """Configuration container for Vectis Next obfuscation and virtualization pipeline."""
    def __init__(
        self,
        virtualize: bool = True,
        poly_mba: bool = True,
        opaque: bool = True,
        dyn_opaque: bool = True,
        rolling_vkey: bool = True,
        vcpu_scramble: bool = True,
        nested_vm: bool = False,
        ephemeral_payload: bool = False,
        state_stepper: str = "nonlinear",
        target_arch: str = "visa_v2",
        extra_flags: Optional[List[str]] = None
    ):
        self.virtualize = virtualize
        self.poly_mba = poly_mba
        self.opaque = opaque
        self.dyn_opaque = dyn_opaque
        self.rolling_vkey = rolling_vkey
        self.vcpu_scramble = vcpu_scramble
        self.nested_vm = nested_vm
        self.ephemeral_payload = ephemeral_payload
        self.state_stepper = state_stepper
        self.target_arch = target_arch
        self.extra_flags = extra_flags or []

    @classmethod
    def from_yaml(cls, path: str) -> "VectisConfig":
        with open(path, "r") as f:
            data = yaml.safe_load(f) or {}
        return cls(**data)

    def to_cli_args(self) -> List[str]:
        args = []
        if self.virtualize: args.append("--virtualize")
        if self.poly_mba: args.append("--poly-mba")
        if self.opaque: args.append("--opaque")
        if self.dyn_opaque: args.append("--dyn-opaque")
        if self.rolling_vkey: args.append("--rolling-vkey")
        if self.vcpu_scramble: args.append("--vcpu-scramble")
        if self.nested_vm: args.append("--nested-vm")
        if self.ephemeral_payload: args.append("--ephemeral-payload")
        args.extend(self.extra_flags)
        return args


class VectisCompiler:
    """Programmatic compiler and transformation harness."""
    def __init__(self, config: Optional[VectisConfig] = None):
        self.config = config or VectisConfig()

    def protect_c(self, input_c: str, output_c: str) -> str:
        """Transforms C source through Vectis virtualization and obfuscation passes."""
        cmd = [str(VECTIS_MAIN), "-i", str(input_c), "-o", str(output_c)] + self.config.to_cli_args()
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode != 0:
            raise RuntimeError(f"Vectis protection failed: {res.stderr}")
        return output_c

    def build_binary(self, input_c: str, output_bin: str, clang_opt: str = "-O2") -> str:
        """Protects C source and compiles directly to native executable."""
        tmp_c = Path(output_bin).with_suffix(".obf.c")
        self.protect_c(input_c, str(tmp_c))
        cmd = ["clang", "-w", clang_opt, str(tmp_c), "-o", str(output_bin)]
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode != 0:
            raise RuntimeError(f"Native clang compilation failed: {res.stderr}")
        return output_bin

    @staticmethod
    def run_benchmark() -> Dict[str, Any]:
        """Runs the black-box surrogate model benchmark."""
        bench_script = PROJECT_ROOT / "benchmarks/blackbox_behavior_benchmark.py"
        res = subprocess.run(["python3", str(bench_script)], capture_output=True, text=True)
        results_json = PROJECT_ROOT / "benchmarks/blackbox_results.json"
        if results_json.exists():
            with open(results_json, "r") as f:
                return json.load(f)
        return {"raw_output": res.stdout}
