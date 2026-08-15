#!/usr/bin/env python3
"""
mlx_sail_optimizer.py — OcaSorry Sail ISA MLX Neural Optimizer
Trains a deep neural network on the sail_dataset.json to predict quality scores,
then uses gradient-based search to find the optimal parameter sets for each
VCPU type — maximizing uniqueness, entropy, and cryptographic strength.
"""

import argparse
import json
import math
import sys
from pathlib import Path

try:
    import mlx.core as mx
    import mlx.nn as nn
    import mlx.optimizers as optim
    import numpy as np
    HAS_MLX = True
except ImportError:
    HAS_MLX = False
    print("[!] MLX not available — install: pip install mlx")
    sys.exit(1)

# ─── Architecture ─────────────────────────────────────────────────────────────

class SailQualityNet(nn.Module):
    """
    Quality predictor: input dim=9 feature vector -> scalar quality score [0,1].
    4-layer MLP with LayerNorm + GELU + residual skip connections.
    """
    def __init__(self, dim: int = 9, hidden: int = 128):
        super().__init__()
        self.fc1  = nn.Linear(dim, hidden)
        self.ln1  = nn.LayerNorm(hidden)
        self.fc2  = nn.Linear(hidden, hidden)
        self.ln2  = nn.LayerNorm(hidden)
        self.fc3  = nn.Linear(hidden, hidden)
        self.ln3  = nn.LayerNorm(hidden)
        self.fc4  = nn.Linear(hidden, hidden // 2)
        self.head = nn.Linear(hidden // 2, 1)

    def __call__(self, x):
        h1 = nn.gelu(self.ln1(self.fc1(x)))
        h2 = h1 + nn.gelu(self.ln2(self.fc2(h1)))      # residual
        h3 = h2 + nn.gelu(self.ln3(self.fc3(h2)))      # residual
        h4 = nn.gelu(self.fc4(h3))
        return mx.sigmoid(self.head(h4))

class SailParamOptimizer(nn.Module):
    """
    Learnable parameter vector for a given VCPU type.
    Represents the continuous parameter space and outputs feature vectors.
    Trained via gradient ascent to maximize predicted quality.
    """
    def __init__(self, dim: int = 9):
        super().__init__()
        self.params = mx.zeros([dim])

    def __call__(self):
        return mx.sigmoid(self.params)  # clamp [0,1]

# ─── Dataset loading ─────────────────────────────────────────────────────────

def load_dataset(path: str, vcpu: str):
    with open(path) as f:
        data = json.load(f)
    X, Y = [], []
    for sample in data["samples"]:
        if vcpu not in sample["vcpus"]:
            continue
        fv    = sample["vcpus"][vcpu]["feature_vector"]
        score = sample["vcpus"][vcpu]["quality_score"]
        X.append(fv)
        Y.append([score])
    if not X:
        raise ValueError(f"No samples for VCPU '{vcpu}'")
    return (mx.array(np.array(X, dtype=np.float32)),
            mx.array(np.array(Y, dtype=np.float32)))

# ─── Training ─────────────────────────────────────────────────────────────────

def train_quality_net(X, Y, epochs: int = 300, lr: float = 3e-3,
                      batch_size: int = 256, hidden: int = 128):
    n_samples = X.shape[0]
    dim = X.shape[1]
    model = SailQualityNet(dim=dim, hidden=hidden)
    optimizer = optim.AdamW(learning_rate=lr, weight_decay=1e-4)

    def loss_fn(model, x_batch, y_batch):
        preds = model(x_batch)
        return mx.mean((preds - y_batch) ** 2)

    loss_and_grad = nn.value_and_grad(model, loss_fn)

    print(f"  Training quality predictor: n={n_samples} dim={dim} hidden={hidden} epochs={epochs}")
    best_loss = float('inf')

    for epoch in range(epochs):
        # shuffle
        idx = np.random.permutation(n_samples)
        X_s = X[idx.tolist()]
        Y_s = Y[idx.tolist()]

        epoch_losses = []
        for i in range(0, n_samples, batch_size):
            xb = X_s[i:i+batch_size]
            yb = Y_s[i:i+batch_size]
            loss, grads = loss_and_grad(model, xb, yb)
            optimizer.update(model, grads)
            mx.eval(model.parameters(), optimizer.state)
            epoch_losses.append(float(loss))

        avg_loss = sum(epoch_losses) / len(epoch_losses)
        if avg_loss < best_loss:
            best_loss = avg_loss

        if (epoch + 1) % 50 == 0 or epoch == 0:
            preds = model(X[:256])
            corr  = float(mx.mean((preds[:,0] - Y[:256,0])**2))
            print(f"    Epoch {epoch+1:3d}/{epochs}  loss={avg_loss:.5f}  "
                  f"best={best_loss:.5f}  val_mse={corr:.5f}")

    return model

# ─── Gradient-based parameter search ─────────────────────────────────────────

def optimize_params(quality_net, vcpu: str, n_restarts: int = 20,
                    grad_steps: int = 500, lr: float = 5e-3) -> dict:
    """
    Finds optimal continuous parameters by gradient ascent on quality_net.
    Returns the best parameter vector found across n_restarts.
    """
    best_score  = -1.0
    best_params = None

    for restart in range(n_restarts):
        # Random initialization
        init = mx.array(np.random.uniform(0.1, 0.9, [9]).astype(np.float32))
        params = mx.array(init.tolist())
        # Manual gradient ascent (maximize quality = minimize -quality)
        for step in range(grad_steps):
            p_sig = mx.sigmoid(params)
            pred  = quality_net(p_sig[None])[0, 0]
            loss  = -pred   # ascent
            # finite differences for params (MLX doesn't support nn.value_and_grad on bare arrays easily)
            grads = np.zeros(9, dtype=np.float32)
            eps = 1e-3
            for i in range(9):
                p_plus = params.tolist()
                p_plus[i] += eps
                p_minus = params.tolist()
                p_minus[i] -= eps
                vp = float(quality_net(mx.sigmoid(mx.array(p_plus))[None])[0, 0])
                vm = float(quality_net(mx.sigmoid(mx.array(p_minus))[None])[0, 0])
                grads[i] = (vp - vm) / (2 * eps)
            params = mx.array((np.array(params.tolist()) + lr * grads).astype(np.float32))
            # Clamp raw params to avoid extreme sigmoid saturation
            params = mx.clip(params, -5.0, 5.0)

        final = mx.sigmoid(params)
        score = float(quality_net(final[None])[0, 0])
        if score > best_score:
            best_score  = score
            best_params = final.tolist()

        if (restart + 1) % 5 == 0:
            print(f"    Restart {restart+1:2d}/{n_restarts}  best_score={best_score:.4f}")

    return {"params": best_params, "predicted_quality": best_score}

# ─── Parameter decoding ───────────────────────────────────────────────────────

GF_POLYS = [0x1B, 0x1D, 0x4D, 0x8D, 0xA3, 0xC5]

def decode_params(vcpu: str, fvec: list[float]) -> dict:
    """Convert normalised [0,1] parameter vector back to concrete values."""
    if vcpu == 'visa':
        gf_idx   = min(int(fvec[0] * len(GF_POLYS)), len(GF_POLYS)-1)
        imm_idx  = min(int(fvec[2] * 3), 2)
        return {
            "gf_poly":        hex(GF_POLYS[gf_idx]),
            "rol_const":      max(1, min(15, round(fvec[1] * 15))),
            "imm_bits":       [12, 14, 16][imm_idx],
            "opcode_entropy": round(fvec[3] * 4.0, 3),
            "mnemonic_entropy": round(fvec[4] * 6.0, 3),
            "syllable_count": round(fvec[5] * 32),
        }
    if vcpu == 'nested':
        hb_idx = min(int(fvec[0] * 3), 2)
        return {
            "hash_bits":   [32, 48, 64][hb_idx],
            "stack_depth": max(4, min(16, round(fvec[1] * 16))),
            "state_regs":  max(4, min(12, round(fvec[2] * 12))),
            "mnemonic_entropy": round(fvec[3] * 6.0, 3),
            "outer_ops":   max(4, round(fvec[4] * 8)),
            "inner_ops":   max(4, round(fvec[5] * 14)),
        }
    if vcpu == 'rolling':
        kb_idx = min(int(fvec[0] * 3), 2)
        gf_idx = min(int(fvec[2] * len(GF_POLYS)), len(GF_POLYS)-1)
        lcg_mults = [17, 31, 33, 65]
        lm_idx = min(int(fvec[3] * len(lcg_mults)), len(lcg_mults)-1)
        return {
            "key_bits":    [32, 48, 64][kb_idx],
            "state_regs":  max(4, min(8, round(fvec[1] * 8))),
            "gf_poly":     hex(GF_POLYS[gf_idx]),
            "lcg_mult":    lcg_mults[lm_idx],
            "mnemonic_entropy": round(fvec[5] * 6.0, 3),
            "rk_ops":      max(4, round(fvec[6] * 12)),
        }
    if vcpu == 'ephemeral':
        return {
            "page_shift":  12 + min(int(fvec[0] * 4), 3),
            "wipe_passes": max(2, min(6, round(fvec[1] * 6))),
            "jit_regs":    max(4, min(7, round(fvec[2] * 7))),
            "mnemonic_entropy": round(fvec[4] * 6.0, 3),
            "ep_ops":      max(4, round(fvec[5] * 12)),
            "jit_states":  max(4, round(fvec[6] * 12)),
        }
    return {}

# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description="OcaSorry Sail ISA MLX Optimizer")
    ap.add_argument("--dataset",    default="tools/sail_dataset.json")
    ap.add_argument("--epochs",     type=int, default=300)
    ap.add_argument("--restarts",   type=int, default=20)
    ap.add_argument("--grad-steps", type=int, default=500)
    ap.add_argument("--hidden",     type=int, default=128)
    ap.add_argument("--lr-train",   type=float, default=3e-3)
    ap.add_argument("--lr-opt",     type=float, default=5e-3)
    ap.add_argument("--output",     default="tools/sail_optimal_params.json")
    ap.add_argument("--vcpu",       default="all",
                    choices=["all", "visa", "nested", "rolling", "ephemeral"])
    args = ap.parse_args()

    dataset_path = Path(args.dataset)
    if not dataset_path.exists():
        print(f"[!] Dataset not found: {dataset_path}")
        print(f"    Run: python3 tools/sail_dataset_gen.py -n 2000")
        sys.exit(1)

    vcpu_types = (["visa", "nested", "rolling", "ephemeral"]
                  if args.vcpu == "all" else [args.vcpu])

    results = {}

    for vcpu in vcpu_types:
        print(f"\n{'='*60}")
        print(f"  VCPU: {vcpu.upper()}")
        print(f"{'='*60}")

        try:
            X, Y = load_dataset(args.dataset, vcpu)
        except ValueError as e:
            print(f"  [!] {e}")
            continue

        print(f"  Dataset: {X.shape[0]} samples, dim={X.shape[1]}")
        print(f"  Score range: [{float(Y.min()):.3f}, {float(Y.max()):.3f}]")
        print(f"  Score mean:  {float(mx.mean(Y)):.3f}")

        # Train quality predictor
        print(f"\n[1] Training quality predictor...")
        net = train_quality_net(X, Y,
                                epochs=args.epochs,
                                lr=args.lr_train,
                                hidden=args.hidden)

        # Evaluate on dataset
        all_preds = net(X)
        train_mse = float(mx.mean((all_preds - Y) ** 2))
        print(f"  Final train MSE: {train_mse:.6f}")

        # Find top-K actual samples
        scores_np = np.array(Y.tolist()).flatten()
        top_k_idx = np.argsort(scores_np)[::-1][:5]
        print(f"\n  Top-5 actual samples (seeds):")

        # Load top seeds for reference
        with open(args.dataset) as f:
            raw = json.load(f)
        vcpu_samples = [(s["seed"], s["vcpus"][vcpu])
                        for s in raw["samples"] if vcpu in s["vcpus"]]
        vcpu_samples.sort(key=lambda x: x[1]["quality_score"], reverse=True)
        for seed, sv in vcpu_samples[:5]:
            print(f"    seed={seed:6d}  score={sv['quality_score']:.4f}  "
                  f"feats={sv['features']}")

        # Gradient-based parameter optimization
        print(f"\n[2] Gradient-based parameter search ({args.restarts} restarts × {args.grad_steps} steps)...")
        opt_result = optimize_params(net, vcpu,
                                     n_restarts=args.restarts,
                                     grad_steps=args.grad_steps,
                                     lr=args.lr_opt)

        # Decode to concrete values
        decoded = decode_params(vcpu, opt_result["params"])

        print(f"\n  ★ Optimal parameters for {vcpu.upper()}:")
        print(f"    predicted_quality = {opt_result['predicted_quality']:.4f}")
        for k, v in decoded.items():
            print(f"    {k:22s} = {v}")

        results[vcpu] = {
            "predicted_quality": opt_result["predicted_quality"],
            "feature_vector":    opt_result["params"],
            "optimal_params":    decoded,
            "train_mse":         train_mse,
            "dataset_mean_score": float(mx.mean(Y)),
            "dataset_max_score":  float(Y.max()),
        }

    # Save results
    out_path = Path(args.output)
    with open(out_path, "w") as f:
        json.dump(results, f, indent=2)
    print(f"\n{'='*60}")
    print(f"[+] Optimal parameters saved -> {out_path}")
    print(f"\n[Summary]")
    for vcpu, r in results.items():
        print(f"  {vcpu:10s}  quality={r['predicted_quality']:.4f}  "
              f"(dataset_max={r['dataset_max_score']:.3f})")

if __name__ == "__main__":
    main()
