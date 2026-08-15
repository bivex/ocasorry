#!/usr/bin/env python3
"""
mlx_sail_optimizer.py — Enterprise Deep MLX Neural Optimizer for Sail ISAs
Features:
- Disjoint Train/Val Split (85/15) with genuine out-of-sample validation
- Model Checkpointing (restores exact weights at minimum validation loss)
- Dropout (p=0.1) & Early Stopping with patience
- Deep Ensemble (3-5 models) with Pessimistic UCB/LCB scoring (Mean - 1.5 * Std)
- In-Distribution Manifold Regularization (penalizes distance from training data)
- Z-Score Feature Standardization (mean/std per dimension)
- Cosine Annealing LR Schedule & Vectorized Multi-Start GPU Gradient Ascent (250 restarts)
"""

import argparse
import copy
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
    def __init__(self, dim: int = 9, hidden: int = 128, drop_p: float = 0.1):
        super().__init__()
        self.fc1  = nn.Linear(dim, hidden)
        self.ln1  = nn.LayerNorm(hidden)
        self.fc2  = nn.Linear(hidden, hidden)
        self.ln2  = nn.LayerNorm(hidden)
        self.fc3  = nn.Linear(hidden, hidden)
        self.ln3  = nn.LayerNorm(hidden)
        self.fc4  = nn.Linear(hidden, hidden // 2)
        self.head = nn.Linear(hidden // 2, 1)
        self.drop = nn.Dropout(drop_p)

    def __call__(self, x):
        h1 = self.drop(nn.gelu(self.ln1(self.fc1(x))))
        h2 = h1 + self.drop(nn.gelu(self.ln2(self.fc2(h1))))
        h3 = h2 + self.drop(nn.gelu(self.ln3(self.fc3(h2))))
        h4 = nn.gelu(self.fc4(h3))
        return mx.sigmoid(self.head(h4))

# ─── Dataset Loading with Real Train/Val Split & Normalization ────────────────

def load_dataset(path: str, vcpu: str, val_frac: float = 0.15, seed: int = 42):
    with open(path) as f:
        data = json.load(f)
    X, Y = [], []
    for sample in data["samples"]:
        if vcpu not in sample["vcpus"]:
            continue
        X.append(sample["vcpus"][vcpu]["feature_vector"])
        Y.append([sample["vcpus"][vcpu]["quality_score"]])
    if not X:
        raise ValueError(f"No samples for VCPU '{vcpu}'")

    X_np = np.array(X, dtype=np.float32)
    Y_np = np.array(Y, dtype=np.float32)
    n_samples = len(X_np)

    rng = np.random.RandomState(seed)
    perm = rng.permutation(n_samples)
    n_val = max(1, int(n_samples * val_frac))
    val_idx, train_idx = perm[:n_val], perm[n_val:]

    # Compute standardization stats strictly on training set
    x_mean = X_np[train_idx].mean(axis=0, keepdims=True)
    x_std  = X_np[train_idx].std(axis=0, keepdims=True) + 1e-6

    X_train_norm = (X_np[train_idx] - x_mean) / x_std
    X_val_norm   = (X_np[val_idx] - x_mean) / x_std

    stats = {"mean": x_mean.flatten().tolist(), "std": x_std.flatten().tolist()}

    return (mx.array(X_train_norm), mx.array(Y_np[train_idx]),
            mx.array(X_val_norm),   mx.array(Y_np[val_idx]),
            stats, X_np[train_idx])

# ─── Training with Checkpointing, Cosine LR & Early Stopping ───────────────────

def train_single_model(X_tr, Y_tr, X_val, Y_val, epochs=300, lr=3e-3,
                       batch_size=128, hidden=128, patience=40, model_id=1):
    n_tr = X_tr.shape[0]
    dim = X_tr.shape[1]
    model = SailQualityNet(dim=dim, hidden=hidden, drop_p=0.1)
    optimizer = optim.AdamW(learning_rate=lr, weight_decay=1e-4)

    def loss_fn(model, xb, yb):
        preds = model(xb)
        return mx.mean((preds - yb) ** 2)

    loss_and_grad = nn.value_and_grad(model, loss_fn)
    best_val_loss = float('inf')
    best_weights = None
    no_improve = 0

    for epoch in range(1, epochs + 1):
        # Cosine learning rate decay
        cos_lr = lr * 0.5 * (1.0 + math.cos(math.pi * epoch / epochs))
        optimizer.learning_rate = max(cos_lr, 1e-5)

        # Train mini-batches
        idx = np.random.permutation(n_tr)
        for i in range(0, n_tr, batch_size):
            xb = X_tr[idx[i:i+batch_size].tolist()]
            yb = Y_tr[idx[i:i+batch_size].tolist()]
            loss, grads = loss_and_grad(model, xb, yb)
            optimizer.update(model, grads)
            mx.eval(model.parameters(), optimizer.state)

        # Genuine Out-of-Sample Validation evaluation
        val_preds = model(X_val)
        val_loss = float(mx.mean((val_preds - Y_val) ** 2))

        if val_loss < best_val_loss:
            best_val_loss = val_loss
            # Checkpoint exact best parameters
            best_weights = copy.deepcopy(model.parameters())
            no_improve = 0
        else:
            no_improve += 1

        if epoch % 50 == 0 or epoch == epochs or no_improve == patience:
            tr_loss = float(mx.mean((model(X_tr) - Y_tr) ** 2))
            bar = "=" * (epoch * 15 // epochs) + "-" * (15 - epoch * 15 // epochs)
            print(f"    [Net {model_id} | Ep {epoch:3d}/{epochs:3d}] [{bar}] Tr MSE: {tr_loss:.6f} | Val MSE: {val_loss:.6f} (Best: {best_val_loss:.6f})", flush=True)

        if no_improve >= patience and epoch >= 100:
            print(f"    [Net {model_id}] Early stopping triggered at epoch {epoch} (best val MSE: {best_val_loss:.6f})", flush=True)
            break

    # Restore exact best weights
    if best_weights is not None:
        model.update(best_weights)
        mx.eval(model.parameters())

    return model, best_val_loss

# ─── Robust Ensemble Optimization with In-Distribution Regularization ─────────

def optimize_ensemble_params(models, stats, raw_train_X, n_restarts=250,
                             grad_steps=500, lr=0.03, alpha_dist=0.15):
    """
    Optimizes candidate parameters against an ensemble of models using
    Conservative Lower Confidence Bound (Mean - 1.5 * Std) and an
    In-Distribution distance penalty to prevent adversarial surrogate gaming.
    """
    print(f"\n[2] Executing Vectorized GPU Ensemble Gradient Search ({n_restarts} restarts, alpha_dist={alpha_dist})...", flush=True)
    t0 = time.time()

    x_mean = mx.array(stats["mean"])
    x_std  = mx.array(stats["std"])
    train_mean = mx.mean(mx.array(raw_train_X), axis=0)

    # Vectorized initial parameter states: [n_restarts, 9] in unconstrained space
    init_np = np.random.uniform(-1.0, 1.0, (n_restarts, 9)).astype(np.float32)
    params = mx.array(init_np)

    def ensemble_objective(p_batch):
        # Raw parameter bounded in [0, 1]
        p_sig = mx.sigmoid(p_batch)
        # Normalize into model input feature space
        p_norm = (p_sig - x_mean) / x_std

        # Gather predictions across all ensemble models
        all_scores = [m(p_norm) for m in models]
        stacked = mx.concatenate(all_scores, axis=1) # [n_restarts, n_models]

        ens_mean = mx.mean(stacked, axis=1)
        ens_std  = mx.sqrt(mx.mean((stacked - ens_mean[:, None]) ** 2, axis=1) + 1e-8)

        # Pessimistic conservative score: Mean - 1.5 * Uncertainty
        conservative_score = ens_mean - 1.5 * ens_std

        # In-distribution penalty: distance from empirical training center
        dist_penalty = mx.mean((p_sig - train_mean) ** 2, axis=1)

        total_reward = conservative_score - alpha_dist * dist_penalty
        return -mx.sum(total_reward)

    grad_fn = mx.grad(ensemble_objective)
    best_score = -1.0
    best_params = None

    for step in range(1, grad_steps + 1):
        cos_lr = lr * 0.5 * (1.0 + math.cos(math.pi * step / grad_steps))
        grads = grad_fn(params)
        params = params - max(cos_lr, 1e-4) * grads
        params = mx.clip(params, -5.0, 5.0)
        mx.eval(params)

        if step % 100 == 0 or step == grad_steps:
            p_sig = mx.sigmoid(params)
            p_norm = (p_sig - x_mean) / x_std
            all_scores = [m(p_norm) for m in models]
            stacked = mx.concatenate(all_scores, axis=1)
            ens_mean = mx.mean(stacked, axis=1)
            ens_std  = mx.sqrt(mx.mean((stacked - ens_mean[:, None]) ** 2, axis=1) + 1e-8)
            pessimistic = (ens_mean - 1.5 * ens_std)
            mx.eval(pessimistic)

            max_idx = int(mx.argmax(pessimistic))
            cur_best = float(pessimistic[max_idx])
            cur_mean = float(ens_mean[max_idx])
            cur_std  = float(ens_std[max_idx])

            if cur_best > best_score:
                best_score = cur_best
                best_params = p_sig[max_idx].tolist()

            elapsed = time.time() - t0
            print(f"    [Step {step:3d}/{grad_steps:3d}] Best Robust Score: {best_score:.5f} (Mean: {cur_mean:.4f}, Std: {cur_std:.4f}) | {elapsed:.2f}s", flush=True)

    return {"params": best_params, "robust_quality": best_score}

# ─── Parameter Decoding ───────────────────────────────────────────────────────

GF_POLYS = [0x1B, 0x1D, 0x4D, 0x8D, 0xA3, 0xC5]

def decode_params(vcpu: str, fvec: list[float]) -> dict:
    if vcpu == 'visa':
        gf_idx  = min(int(fvec[0] * len(GF_POLYS)), len(GF_POLYS)-1)
        imm_idx = min(int(fvec[2] * 3), 2)
        return {
            "gf_poly": hex(GF_POLYS[gf_idx]),
            "rol_const": max(1, min(15, round(fvec[1] * 15))),
            "imm_bits": [12, 14, 16][imm_idx],
            "opcode_entropy": round(fvec[3] * 4.0, 3),
            "mnemonic_entropy": round(fvec[4] * 6.0, 3),
            "syllable_count": max(12, min(32, round(fvec[5] * 32))),
        }
    if vcpu == 'nested':
        hb_idx = min(int(fvec[0] * 3), 2)
        return {
            "hash_bits": [32, 48, 64][hb_idx],
            "stack_depth": max(4, min(16, round(fvec[1] * 16))),
            "state_regs": max(4, min(12, round(fvec[2] * 12))),
            "mnemonic_entropy": round(fvec[3] * 6.0, 3),
            "outer_ops": max(4, round(fvec[4] * 8)),
            "inner_ops": max(4, round(fvec[5] * 14)),
        }
    if vcpu == 'rolling':
        kb_idx = min(int(fvec[0] * 3), 2)
        gf_idx = min(int(fvec[2] * len(GF_POLYS)), len(GF_POLYS)-1)
        lcg_mults = [17, 31, 33, 65]
        lm_idx = min(int(fvec[3] * len(lcg_mults)), len(lcg_mults)-1)
        return {
            "key_bits": [32, 48, 64][kb_idx],
            "state_regs": max(4, min(8, round(fvec[1] * 8))),
            "gf_poly": hex(GF_POLYS[gf_idx]),
            "lcg_mult": lcg_mults[lm_idx],
            "mnemonic_entropy": round(fvec[5] * 6.0, 3),
            "rk_ops": max(4, round(fvec[6] * 12)),
        }
    if vcpu == 'ephemeral':
        return {
            "page_shift": 12 + min(int(fvec[0] * 4), 3),
            "wipe_passes": max(2, min(6, round(fvec[1] * 6))),
            "jit_regs": max(4, min(7, round(fvec[2] * 7))),
            "mnemonic_entropy": round(fvec[4] * 6.0, 3),
            "ep_ops": max(4, round(fvec[5] * 12)),
            "jit_states": max(4, round(fvec[6] * 12)),
        }
    return {}

# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description="OcaSorry Enterprise Sail MLX Optimizer")
    ap.add_argument("--dataset", default="tools/sail_dataset.json")
    ap.add_argument("--ensemble-size", type=int, default=3, help="Number of models in ensemble")
    ap.add_argument("--epochs", type=int, default=300)
    ap.add_argument("--restarts", type=int, default=250, help="Vectorized GPU restarts")
    ap.add_argument("--grad-steps", type=int, default=500)
    ap.add_argument("--hidden", type=int, default=128)
    ap.add_argument("--lr-train", type=float, default=3e-3)
    ap.add_argument("--lr-opt", type=float, default=0.03)
    ap.add_argument("--seed", type=int, default=42, help="Global seed")
    ap.add_argument("--output", default="tools/sail_optimal_params.json")
    ap.add_argument("--vcpu", default="all", choices=["all", "visa", "nested", "rolling", "ephemeral"])
    args = ap.parse_args()

    np.random.seed(args.seed)
    mx.random.seed(args.seed)

    dataset_path = Path(args.dataset)
    if not dataset_path.exists():
        print(f"[!] Dataset not found: {dataset_path}", flush=True)
        sys.exit(1)

    vcpu_types = ["visa", "nested", "rolling", "ephemeral"] if args.vcpu == "all" else [args.vcpu]
    results = {}

    for vcpu in vcpu_types:
        print(f"\n{'='*70}", flush=True)
        print(f"  VCPU ARCHITECTURE: {vcpu.upper()} (Ensemble Size: {args.ensemble_size}, Seed: {args.seed})", flush=True)
        print(f"{'='*70}", flush=True)

        X_tr, Y_tr, X_val, Y_val, stats, raw_train_X = load_dataset(
            args.dataset, vcpu, val_frac=0.15, seed=args.seed
        )

        print(f"  Dataset: {X_tr.shape[0]} Train / {X_val.shape[0]} Val (dim={X_tr.shape[1]})", flush=True)
        print(f"  Validation Score Range: [{float(Y_val.min()):.3f}, {float(Y_val.max()):.3f}]", flush=True)

        # Train Deep Ensemble
        print(f"\n[1] Training Deep Ensemble ({args.ensemble_size} models with genuine validation split)...", flush=True)
        models, val_losses = [], []
        for m_id in range(1, args.ensemble_size + 1):
            m, v_loss = train_single_model(
                X_tr, Y_tr, X_val, Y_val,
                epochs=args.epochs, lr=args.lr_train, hidden=args.hidden,
                patience=45, model_id=m_id
            )
            models.append(m)
            val_losses.append(v_loss)

        avg_val_mse = sum(val_losses) / len(val_losses)
        print(f"  [+] Ensemble Training Complete! Mean Val MSE: {avg_val_mse:.6f}", flush=True)

        # Search optimal parameters
        opt_res = optimize_ensemble_params(
            models, stats, raw_train_X,
            n_restarts=args.restarts, grad_steps=args.grad_steps,
            lr=args.lr_opt, alpha_dist=0.15
        )

        decoded = decode_params(vcpu, opt_res["params"])

        print(f"\n  ★ ROBUST ENSEMBLE OPTIMAL CONFIGURATION FOR {vcpu.upper()}:", flush=True)
        print(f"    Pessimistic Score (Mean - 1.5*Std) = {opt_res['robust_quality']:.5f}", flush=True)
        for k, v in decoded.items():
            print(f"    {k:22s} = {v}", flush=True)

        results[vcpu] = {
            "robust_quality": opt_res["robust_quality"],
            "feature_vector": opt_res["params"],
            "optimal_params": decoded,
            "mean_val_mse":   avg_val_mse,
            "dataset_val_max": float(Y_val.max()),
        }

    out_path = Path(args.output)
    with open(out_path, "w") as f:
        json.dump(results, f, indent=2)

    print(f"\n{'='*70}", flush=True)
    print(f"[+] Verified and Regularized Sail Configurations Saved -> {out_path}", flush=True)

if __name__ == "__main__":
    main()
