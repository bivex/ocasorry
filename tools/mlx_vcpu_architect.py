#!/usr/bin/env python3
"""
==============================================================================
  OcaSorry - MLX Neural VCPU & Profile Architect (Apple Silicon Accelerated)
  Deep Neural Network / Policy Network built with Apple MLX that designs
  optimal multi-tier VCPU architectures, ISA parameters, and hardening profiles
  for given binary size constraints, latency budgets, and adversary threat levels.
==============================================================================
"""

import os
import sys
import json
import time
import argparse
from typing import Dict, Any, List, Tuple
import numpy as np

try:
    import mlx.core as mx
    import mlx.nn as nn
    import mlx.optimizers as opt
except ImportError:
    print("[!] Error: MLX is required. Install via: pip install mlx")
    sys.exit(1)

PROFILE_NAMES = [
    "compact",
    "standard",
    "hardened-128k",
    "fortress-256k",
    "titan-512k",
    "colossus-1m"
]

VCPU_TIER_TYPES = [
    "visa",
    "nested_vm",
    "rolling_vkey",
    "ephemeral_jit"
]


class VCPUArchitectMLX(nn.Module):
    """
    Apple MLX Multi-Head Neural Architecture for VCPU Synthesis:
    - Input Features: [TargetSizeKB, LatencyBudgetUS, ThreatLevel, FuncComplexity, AstNodes, LoopCount]
    - Head 1: Profile Category Logits (Classification over 6 profiles)
    - Head 2: Continuous VCPU Parameters (DispatchSize, MBADepth, DecoyDensity, LUTCount, VRegCount)
    - Head 3: Multi-VCPU Cascade Tiers Distribution (4-dimensional probability over VCPU types)
    - Head 4: Surrogate Security & Resilience Score (0..100)
    """
    def __init__(self, in_features: int = 6, hidden_dim: int = 128):
        super().__init__()
        # Shared Feature Extractor with LayerNorm & GELU
        self.fc1 = nn.Linear(in_features, hidden_dim)
        self.ln1 = nn.LayerNorm(hidden_dim)
        self.fc2 = nn.Linear(hidden_dim, hidden_dim)
        self.ln2 = nn.LayerNorm(hidden_dim)
        self.fc3 = nn.Linear(hidden_dim, hidden_dim)
        self.ln3 = nn.LayerNorm(hidden_dim)

        # Head 1: Profile Classifier (6 classes)
        self.head_profile = nn.Linear(hidden_dim, len(PROFILE_NAMES))

        # Head 2: Continuous Parameters Regressor (5 parameters: dispatch, mba, decoys, luts, vregs)
        self.head_params = nn.Linear(hidden_dim, 5)

        # Head 3: Multi-VCPU Cascade Policy (4 probabilities for VCPU tiers)
        self.head_tiers = nn.Linear(hidden_dim, 4)

        # Head 4: Surrogate Resilience Evaluator (1 value: estimated SMT resistance %)
        self.head_security = nn.Linear(hidden_dim, 1)

    def __call__(self, x: mx.array) -> Tuple[mx.array, mx.array, mx.array, mx.array]:
        h = nn.gelu(self.ln1(self.fc1(x)))
        h = h + nn.gelu(self.ln2(self.fc2(h)))  # Residual connection
        h = h + nn.gelu(self.ln3(self.fc3(h)))  # Residual connection

        logits_profile = self.head_profile(h)
        reg_params = nn.sigmoid(self.head_params(h))  # Normalized to [0, 1]
        logits_tiers = self.head_tiers(h)
        security_score = nn.sigmoid(self.head_security(h)) * 100.0

        return logits_profile, reg_params, logits_tiers, security_score


def generate_synthetic_compiler_dataset(n_samples: int = 5000) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Generates compiler telemetry dataset for supervised pre-training"""
    np.random.seed(42)
    # Features:
    # 0: TargetSizeKB (32..2048)
    # 1: LatencyBudgetUS (10..50000)
    # 2: ThreatLevel (1: Low, 2: Med, 3: High, 4: Military)
    # 3: FuncComplexity (1..10)
    # 4: AstNodes (50..2000)
    # 5: LoopCount (0..20)
    X = np.zeros((n_samples, 6), dtype=np.float32)
    X[:, 0] = np.random.uniform(32.0, 2048.0, n_samples)
    X[:, 1] = np.random.uniform(100.0, 50000.0, n_samples)
    X[:, 2] = np.random.randint(1, 5, n_samples).astype(np.float32)
    X[:, 3] = np.random.uniform(1.0, 10.0, n_samples)
    X[:, 4] = np.random.uniform(50.0, 2000.0, n_samples)
    X[:, 5] = np.random.randint(0, 20, n_samples).astype(np.float32)

    # Ground truth targets
    y_profile = np.zeros((n_samples,), dtype=np.int32)
    y_params = np.zeros((n_samples, 5), dtype=np.float32)
    y_tiers = np.zeros((n_samples, 4), dtype=np.float32)
    y_sec = np.zeros((n_samples, 1), dtype=np.float32)

    for i in range(n_samples):
        size_kb = X[i, 0]
        threat = X[i, 2]

        if size_kb < 80.0 or threat == 1:
            prof_idx = 0  # compact
            dispatch = 64
            mba = 1
            decoys = 2
            luts = 0
            vregs = 16
            tiers = [1.0, 0.0, 0.0, 0.0]
            sec = 45.0
        elif size_kb < 140.0:
            prof_idx = 1  # standard
            dispatch = 64
            mba = 2
            decoys = 5
            luts = 1
            vregs = 32
            tiers = [0.4, 0.3, 0.2, 0.1]
            sec = 65.0
        elif size_kb < 220.0:
            prof_idx = 2  # hardened-128k
            dispatch = 128
            mba = 2
            decoys = 10
            luts = 4
            vregs = 48
            tiers = [0.3, 0.3, 0.2, 0.2]
            sec = 78.0
        elif size_kb < 400.0:
            prof_idx = 3  # fortress-256k
            dispatch = 256
            mba = 3
            decoys = 25
            luts = 8
            vregs = 64
            tiers = [0.25, 0.25, 0.25, 0.25]
            sec = 88.0
        elif size_kb < 800.0 or threat == 4:
            prof_idx = 4  # titan-512k
            dispatch = 512
            mba = 4
            decoys = 50
            luts = 16
            vregs = 64
            tiers = [0.25, 0.25, 0.25, 0.25]
            sec = 96.5
        else:
            prof_idx = 5  # colossus-1m
            dispatch = 512
            mba = 4
            decoys = 100
            luts = 32
            vregs = 64
            tiers = [0.25, 0.25, 0.25, 0.25]
            sec = 99.2

        y_profile[i] = prof_idx
        # Normalize continuous parameters into [0, 1]
        y_params[i, 0] = (dispatch - 64) / (512 - 64)
        y_params[i, 1] = (mba - 1) / (4 - 1)
        y_params[i, 2] = (decoys - 2) / (100 - 2)
        y_params[i, 3] = luts / 32.0
        y_params[i, 4] = (vregs - 16) / (64 - 16)
        y_tiers[i] = tiers
        y_sec[i, 0] = sec

    # Feature normalization
    X_norm = np.copy(X)
    X_norm[:, 0] = (X[:, 0] - 32.0) / (2048.0 - 32.0)
    X_norm[:, 1] = (X[:, 1] - 100.0) / (50000.0 - 100.0)
    X_norm[:, 2] = (X[:, 2] - 1.0) / 3.0
    X_norm[:, 3] = (X[:, 3] - 1.0) / 9.0
    X_norm[:, 4] = (X[:, 4] - 50.0) / 1950.0
    X_norm[:, 5] = X[:, 5] / 20.0

    return X_norm, y_profile, y_params, y_tiers, y_sec


def train_mlx_model(model: VCPUArchitectMLX, epochs: int = 15, batch_size: int = 64) -> None:
    """Trains the MLX neural network on Metal GPU"""
    print("[*] Generating synthetic compiler telemetry & Pareto dataset (5,000 samples)...")
    X_np, y_prof_np, y_param_np, y_tier_np, y_sec_np = generate_synthetic_compiler_dataset(5000)

    X = mx.array(X_np)
    y_prof = mx.array(y_prof_np)
    y_param = mx.array(y_param_np)
    y_tier = mx.array(y_tier_np)
    y_sec = mx.array(y_sec_np)

    optimizer = opt.AdamW(learning_rate=1e-3, weight_decay=1e-4)

    def loss_fn(m, x_b, yp_b, ypar_b, ytier_b, ysec_b):
        logits_p, pred_par, logits_t, pred_sec = m(x_b)
        loss_p = nn.losses.cross_entropy(logits_p, yp_b, reduction="mean")
        loss_par = nn.losses.mse_loss(pred_par, ypar_b, reduction="mean")
        loss_t = nn.losses.mse_loss(nn.softmax(logits_t, axis=-1), ytier_b, reduction="mean")
        loss_sec = nn.losses.mse_loss(pred_sec, ysec_b, reduction="mean") / 100.0
        return loss_p + (2.0 * loss_par) + (1.5 * loss_t) + (0.5 * loss_sec)

    loss_and_grad_fn = nn.value_and_grad(model, loss_fn)

    n_batches = len(X) // batch_size
    print(f"[*] Training MLX Neural Network on Apple Silicon Metal GPU ({epochs} epochs, {n_batches} batches/epoch)...")

    t0 = time.time()
    for epoch in range(epochs):
        perm = np.random.permutation(len(X))
        epoch_loss = 0.0
        for b in range(n_batches):
            idx = perm[b * batch_size : (b + 1) * batch_size]
            idx_mx = mx.array(idx)
            x_b = X[idx_mx]
            yp_b = y_prof[idx_mx]
            ypar_b = y_param[idx_mx]
            ytier_b = y_tier[idx_mx]
            ysec_b = y_sec[idx_mx]

            loss, grads = loss_and_grad_fn(model, x_b, yp_b, ypar_b, ytier_b, ysec_b)
            optimizer.update(model, grads)
            mx.eval(model.parameters(), optimizer.state)
            epoch_loss += loss.item()

        avg_loss = epoch_loss / n_batches
        if (epoch + 1) % 3 == 0 or epoch == epochs - 1:
            print(f"    [Epoch {epoch+1:02d}/{epochs:02d}] Multi-Head Loss: {avg_loss:.4f}")

    t1 = time.time()
    print(f"[+] MLX Metal GPU Training Complete in {(t1 - t0):.2f}s!\n")


def design_vcpu_profile(model: VCPUArchitectMLX,
                        target_size_kb: float,
                        latency_budget_us: float,
                        threat_level: int,
                        func_complexity: float,
                        ast_nodes: int,
                        loop_count: int) -> Dict[str, Any]:
    """Runs neural network inference in MLX to design optimal VCPU architecture"""
    x_raw = np.array([[
        (target_size_kb - 32.0) / (2048.0 - 32.0),
        (latency_budget_us - 100.0) / (50000.0 - 100.0),
        (threat_level - 1.0) / 3.0,
        (func_complexity - 1.0) / 9.0,
        (ast_nodes - 50.0) / 1950.0,
        loop_count / 20.0
    ]], dtype=np.float32)

    x_mx = mx.array(x_raw)
    logits_p, pred_par, logits_t, pred_sec = model(x_mx)
    mx.eval(logits_p, pred_par, logits_t, pred_sec)

    p_probs = nn.softmax(logits_p, axis=-1).tolist()[0]
    best_p_idx = int(np.argmax(p_probs))
    profile_name = PROFILE_NAMES[best_p_idx]

    params = pred_par.tolist()[0]
    dispatch_size = int(round(64 + params[0] * (512 - 64)))
    # Snap dispatch size to standard power of 2 or pool sizes
    if dispatch_size > 384: dispatch_size = 512
    elif dispatch_size > 192: dispatch_size = 256
    elif dispatch_size > 96: dispatch_size = 128
    else: dispatch_size = 64

    mba_depth = int(round(1 + params[1] * 3))
    decoy_density = int(round(2 + params[2] * 98))
    lut_count = int(round(params[3] * 32))
    vreg_count = int(round(16 + params[4] * 48))

    tier_probs = nn.softmax(logits_t, axis=-1).tolist()[0]
    security_score = float(pred_sec.item())

    # Build multi-tier cascade recommendation
    tier_recommendations = []
    for idx, prob in enumerate(tier_probs):
        tier_recommendations.append({
            "tier_type": VCPU_TIER_TYPES[idx],
            "confidence": round(prob * 100.0, 1),
            "assigned_weight": round(prob, 3)
        })

    return {
        "neural_designed_profile": profile_name,
        "profile_confidence_pct": round(p_probs[best_p_idx] * 100.0, 1),
        "target_size_kb": target_size_kb,
        "predicted_resilience_score": round(security_score, 1),
        "synthesized_vcpu_isa_params": {
            "dispatch_size": dispatch_size,
            "mba_depth": mba_depth,
            "decoy_density": decoy_density,
            "sbox_lut_count": lut_count,
            "virtual_registers": vreg_count
        },
        "multi_vcpu_cascade_distribution": tier_recommendations,
        "recommended_cli_flags": (
            f"--virtualize --nested-vm --rolling-vkey --ephemeral "
            f"--vm-profile {profile_name} "
            f"--literals --cff --irreducible-loop --bcf --anti-debug --timing-check"
        )
    }


def main():
    parser = argparse.ArgumentParser(description="OcaSorry MLX Neural VCPU & Profile Architect")
    parser.add_argument("--target-size", type=float, default=512.0, help="Target binary footprint in KB (e.g. 128, 256, 512, 1024)")
    parser.add_argument("--latency-budget", type=float, default=5000.0, help="Max latency budget in microseconds (default: 5000 us)")
    parser.add_argument("--threat", type=int, default=4, choices=[1, 2, 3, 4], help="Threat Level (1: Low, 2: Med, 3: High, 4: Military/Z3)")
    parser.add_argument("--complexity", type=float, default=8.5, help="Function cyclomatic complexity (1..10)")
    parser.add_argument("--ast-nodes", type=int, default=850, help="Estimated AST nodes count")
    parser.add_argument("--loops", type=int, default=6, help="Number of nested loops in target function")
    parser.add_argument("--epochs", type=int, default=15, help="Number of training epochs on Metal GPU")
    parser.add_argument("--export-json", type=str, default="", help="Export synthesized VCPU spec to JSON file")
    args = parser.parse_args()

    print("=" * 78)
    print("   OcaSorry: MLX Neural VCPU & Hardening Profile Architect (Apple Silicon)  ")
    print("=" * 78)

    model = VCPUArchitectMLX(in_features=6, hidden_dim=128)
    train_mlx_model(model, epochs=args.epochs)

    print(f"[*] Running Neural VCPU Architecture Inference for Target Constraints:")
    print(f"    - Target Size Constraint   : {args.target_size:.1f} KB")
    print(f"    - Latency Budget           : {args.latency_budget:.1f} µs")
    print(f"    - Threat Level             : {args.threat} / 4 (Adversarial SMT / D810 / Pushan)")
    print(f"    - Function AST Complexity  : {args.complexity:.1f}/10 ({args.ast_nodes} nodes, {args.loops} loops)\n")

    result = design_vcpu_profile(
        model,
        target_size_kb=args.target_size,
        latency_budget_us=args.latency_budget,
        threat_level=args.threat,
        func_complexity=args.complexity,
        ast_nodes=args.ast_nodes,
        loop_count=args.loops
    )

    print("=" * 78)
    print("           🧠 NEURAL NETWORK SYNTHESIZED VCPU ARCHITECTURE           ")
    print("=" * 78)
    print(f"  Optimal Hardening Profile : {result['neural_designed_profile'].upper()} (Confidence: {result['profile_confidence_pct']}%)")
    print(f"  SMT & D810 Resilience     : {result['predicted_resilience_score']}%")
    print("\n  Hardware & ISA Parameters:")
    params = result['synthesized_vcpu_isa_params']
    print(f"    * Dispatch Table Size   : {params['dispatch_size']} Slots (Direct Threading)")
    print(f"    * Non-Linear MBA Depth  : Level {params['mba_depth']} (Karatsuba + Affine)")
    print(f"    * Decoy Density         : {params['decoy_density']} Trap Clusters per Function")
    print(f"    * S-Box LUT Tables      : {params['sbox_lut_count']} Embedded S-Boxes (256B each)")
    print(f"    * Virtual Registers     : {params['virtual_registers']} Rotational VRegs")

    print("\n  4-VCPU Federated Cascade Distribution:")
    for tier in result['multi_vcpu_cascade_distribution']:
        bar = "█" * int(tier['confidence'] // 5)
        print(f"    * {tier['tier_type'].ljust(15)} : {tier['confidence']}% [{bar.ljust(20)}]")

    print("\n  Recommended Compiler CLI:")
    print(f"    ocasorry -i source.c -o obf.c {result['recommended_cli_flags']}")
    print("=" * 78 + "\n")

    if args.export_json:
        with open(args.export_json, "w") as f:
            json.dump(result, f, indent=2)
        print(f"[+] Synthesized VCPU architecture spec exported -> {args.export_json}\n")


if __name__ == "__main__":
    main()
