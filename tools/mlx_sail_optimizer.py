#!/usr/bin/env python3
"""
mlx_sail_optimizer.py — OcaSorry Sail ISA MLX Neural Optimizer
Trains a deep neural network on sail_dataset.json with Apple Silicon GPU acceleration
and realtime epoch/progress reporting, then performs GPU gradient ascent to discover
globally optimal parameters for Sail polymorphic ISAs.
"""

import argparse
import json
import math
import sys
import time
from pathlib import Path

try:
    import mlx.core as mx
    import mlx.nn as nn
    import mlx.optimizers as optim
    import numpy as np
    HAS_MLX = True
except ImportError:
    HAS_MLX = False
    print("[!] MLX not available — install: pip install mlx", flush=True)
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

# ─── Training with Realtime Epoch Telemetry ──────────────────────────────────

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

    print(f"  [+] Training on Apple Silicon Metal GPU (samples={n_samples}, dim={dim}, hidden={hidden}, total_epochs={epochs})", flush=True)
    best_loss = float('inf')
    t0 = time.time()

    for epoch in range(1, epochs + 1):
        # Shuffle dataset
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

        # Live Epoch Progress Logging (every 25 epochs or at key milestones)
        if epoch == 1 or epoch % 25 == 0 or epoch == epochs:
            elapsed = time.time() - t0
            progress_pct = (epoch / epochs) * 100.0
            preds = model(X[:256])
            val_mse = float(mx.mean((preds[:, 0] - Y[:256, 0]) ** 2))
            bar_len = 20
            filled = int(bar_len * epoch / epochs)
            bar = "=" * filled + "-" * (bar_len - filled)
            print(f"    [{epoch:3d}/{epochs:3d}] [{bar}] {progress_pct:5.1f}% | Loss: {avg_loss:.6f} | Best: {best_loss:.6f} | Val MSE: {val_mse:.6f} | Time: {elapsed:.2f}s", flush=True)

    return model

# ─── GPU-Accelerated Gradient-Based Parameter Search ──────────────────────────

def optimize_params(quality_net, vcpu: str, n_restarts: int = 50,
                    grad_steps: int = 500, lr: float = 0.02) -> dict:
    """
    GPU vectorized gradient ascent across multiple random restarts simultaneously.
    """
    print(f"\n[2] Executing Vectorized GPU Gradient Search ({n_restarts} restarts × {grad_steps} steps)...", flush=True)
    t0 = time.time()

    # Shape: [n_restarts, 9]
    init_np = np.random.uniform(-1.0, 1.0, (n_restarts, 9)).astype(np.float32)
    params = mx.array(init_np)

    def score_objective(p_batch):
        p_sig = mx.sigmoid(p_batch)
        # QualityNet evaluation on batch
        scores = quality_net(p_sig)
        return -mx.sum(scores)  # Minimize negative score = maximize score

    grad_fn = mx.grad(score_objective)

    best_score = -1.0
    best_params = None

    for step in range(1, grad_steps + 1):
        grads = grad_fn(params)
        # Gradient ascent step: - grads since objective was negative sum
        params = params - lr * grads
        params = mx.clip(params, -6.0, 6.0)
        mx.eval(params)

        if step % 100 == 0 or step == grad_steps:
            p_sig = mx.sigmoid(params)
            scores = quality_net(p_sig)[:, 0]
            mx.eval(scores)
            max_idx = int(mx.argmax(scores))
            cur_max = float(scores[max_idx])
            if cur_max > best_score:
                best_score = cur_max
                best_params = p_sig[max_idx].tolist()
            elapsed = time.time() - t0
            print(f"    [Step {step:3d}/{grad_steps:3d}] Max Score: {cur_max:.5f} | Best So Far: {best_score:.5f} | Time: {elapsed:.2f}s", flush=True)

    return {"params": best_params, "predicted_quality": best_score}

# ─── Parameter decoding ───────────────────────────────────────────────────────

GF_POLYS = [0x1B, 0x1D, 0x4D, 0x8D, 0xA3, 0xC5]

def decode_params(vcpu: str, fvec: list[float]) -> dict:
    """Convert normalised [0,1] parameter vector back to concrete values."""
    if vcpu == 'visa':
        gf_idx   = min(int(fvec[0] * len(GF_POLYS)), len(GF_POLYS)-1)
        imm_idx  = min(int(fvec[2] * 3), 2)
        return {
            "gf_poly":          hex(GF_POLYS[gf_idx]),
            "rol_const":        max(1, min(15, round(fvec[1] * 15))),
            "imm_bits":         [12, 14, 16][imm_idx],
            "opcode_entropy":   round(fvec[3] * 4.0, 3),
            "mnemonic_entropy": round(fvec[4] * 6.0, 3),
            "syllable_count":   round(fvec[5] * 32),
        }
    if vcpu == 'nested':
        hb_idx = min(int(fvec[0] * 3), 2)
        return {
            "hash_bits":        [32, 48, 64][hb_idx],
            "stack_depth":      max(4, min(16, round(fvec[1] * 16))),
            "state_regs":       max(4, min(12, round(fvec[2] * 12))),
            "mnemonic_entropy": round(fvec[3] * 6.0, 3),
            "outer_ops":        max(4, round(fvec[4] * 8)),
            "inner_ops":        max(4, round(fvec[5] * 14)),
        }
    if vcpu == 'rolling':
        kb_idx = min(int(fvec[0] * 3), 2)
        gf_idx = min(int(fvec[2] * len(GF_POLYS)), len(GF_POLYS)-1)
        lcg_mults = [17, 31, 33, 65]
        lm_idx = min(int(fvec[3] * len(lcg_mults)), len(lcg_mults)-1)
        return {
            "key_bits":         [32, 48, 64][kb_idx],
            "state_regs":       max(4, min(8, round(fvec[1] * 8))),
            "gf_poly":          hex(GF_POLYS[gf_idx]),
            "lcg_mult":         lcg_mults[lm_idx],
            "mnemonic_entropy": round(fvec[5] * 6.0, 3),
            "rk_ops":           max(4, round(fvec[6] * 12)),
        }
    if vcpu == 'ephemeral':
        return {
            "page_shift":       12 + min(int(fvec[0] * 4), 3),
            "wipe_passes":      max(2, min(6, round(fvec[1] * 6))),
            "jit_regs":         max(4, min(7, round(fvec[2] * 7))),
            "mnemonic_entropy": round(fvec[4] * 6.0, 3),
            "ep_ops":           max(4, round(fvec[5] * 12)),
            "jit_states":       max(4, round(fvec[6] * 12)),
        }
    return {}

# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description="OcaSorry Sail ISA MLX Optimizer")
    ap.add_argument("--dataset",    default="tools/sail_dataset.json")
    ap.add_argument("--epochs",     type=int, default=300)
    ap.add_argument("--restarts",   type=int, default=50)
    ap.add_argument("--grad-steps", type=int, default=500)
    ap.add_argument("--hidden",     type=int, default=128)
    ap.add_argument("--lr-train",   type=float, default=3e-3)
    ap.add_argument("--lr-opt",     type=float, default=0.02)
    ap.add_argument("--output",     default="tools/sail_optimal_params.json")
    ap.add_argument("--vcpu",       default="all",
                    choices=["all", "visa", "nested", "rolling", "ephemeral"])
    args = ap.parse_args()

    dataset_path = Path(args.dataset)
    if not dataset_path.exists():
        print(f"[!] Dataset not found: {dataset_path}", flush=True)
        print(f"    Run: python3 tools/sail_dataset_gen.py -n 2000", flush=True)
        sys.exit(1)

    vcpu_types = (["visa", "nested", "rolling", "ephemeral"]
                  if args.vcpu == "all" else [args.vcpu])

    results = {}

    for vcpu in vcpu_types:
        print(f"\n{'='*70}", flush=True)
        print(f"  VCPU TIER ARCHITECTURE: {vcpu.upper()}", flush=True)
        print(f"{'='*70}", flush=True)

        try:
            X, Y = load_dataset(args.dataset, vcpu)
        except ValueError as e:
            print(f"  [!] {e}", flush=True)
            continue

        print(f"  Dataset: {X.shape[0]} samples, dim={X.shape[1]}", flush=True)
        print(f"  Score range: [{float(Y.min()):.3f}, {float(Y.max()):.3f}] | Mean: {float(mx.mean(Y)):.3f}", flush=True)

        # Train quality predictor
        print(f"\n[1] Training Neural Quality Predictor (Total Epochs: {args.epochs})...", flush=True)
        net = train_quality_net(X, Y,
                                epochs=args.epochs,
                                lr=args.lr_train,
                                hidden=args.hidden)

        # Evaluate on dataset
        all_preds = net(X)
        train_mse = float(mx.mean((all_preds - Y) ** 2))
        print(f"  [+] Final Training MSE: {train_mse:.6f}", flush=True)

        # Gradient-based parameter optimization
        opt_result = optimize_params(net, vcpu,
                                     n_restarts=args.restarts,
                                     grad_steps=args.grad_steps,
                                     lr=args.lr_opt)

        # Decode to concrete values
        decoded = decode_params(vcpu, opt_result["params"])

        print(f"\n  ★ DISCOVERED OPTIMAL CONFIGURATION FOR {vcpu.upper()}:", flush=True)
        print(f"    Predicted Quality Score = {opt_result['predicted_quality']:.5f}", flush=True)
        for k, v in decoded.items():
            print(f"    {k:22s} = {v}", flush=True)

        results[vcpu] = {
            "predicted_quality":  opt_result["predicted_quality"],
            "feature_vector":     opt_result["params"],
            "optimal_params":     decoded,
            "train_mse":          train_mse,
            "dataset_mean_score": float(mx.mean(Y)),
            "dataset_max_score":  float(Y.max()),
        }

    # Save results
    out_path = Path(args.output)
    with open(out_path, "w") as f:
        json.dump(results, f, indent=2)
    print(f"\n{'='*70}", flush=True)
    print(f"[+] All optimal Sail parameter models saved -> {out_path}", flush=True)
    print(f"\n[Optimal Quality Score Summary]", flush=True)
    for vcpu, r in results.items():
        print(f"  {vcpu:12s}  Predicted Quality: {r['predicted_quality']:.5f}  (Dataset Max: {r['dataset_max_score']:.3f})", flush=True)

if __name__ == "__main__":
    main()
