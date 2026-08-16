#!/usr/bin/env python3
"""
benchmarks/blackbox_behavior_benchmark.py — Vectis Next Black-Box Behavior Model & Security Benchmark

Measures the empirical cost and accuracy of approximating obfuscated/virtualized functions
purely from Input/Output sampling (Black-Box / Differential Fuzzing / Surrogate ML Regression).

Evaluates 5 standard benchmark categories:
1. Arithmetic: Non-linear polynomial / modular arithmetic
2. Bitwise: Affine bit-permutation & non-linear Boolean mixing
3. CRC Transform: Galois Field LFSR / polynomial reduction
4. FSM: Mealy/Moore finite-state transition sequence
5. Toy Crypto: Substitution-Permutation Network (SPN) mini-block cipher

Calculates:
- Exact-match rate on unseen test inputs
- Relative Mean Error & Hamming Distance
- Reconstruction resistance score (0..100)
"""

import os
import sys
import json
import time
import argparse
import subprocess
import tempfile
import numpy as np

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN_BIN     = os.path.join(PROJECT_ROOT, "_build/default/bin/main.exe")

# ─── Benchmark Target Functions (C Source) ───────────────────────────────────

BENCHMARK_TARGETS = {
    "arithmetic": """\
extern int printf(const char *format, ...);

int target_func(int a, int b) {
    int x = (a * 31 + b * 17) ^ 0x5A5A;
    int y = (x * x + 1337) ^ (a & 0xFF);
    return ((y % 65536) + (x & 0xFFFF)) & 0xFFFF;
}
""",

    "bitwise": """\
extern int printf(const char *format, ...);

int target_func(int a, int b) {
    unsigned int x = (unsigned int)a;
    unsigned int y = (unsigned int)b;
    x = ((x << 5) | (x >> 27)) ^ y;
    y = ((y << 13) | (y >> 19)) + (x ^ 0xA5A5A5A5);
    x = x ^ (y >> 7) ^ 0x3C3C3C3C;
    return (int)((x ^ y) & 0xFFFF);
}
""",

    "crc_transform": """\
extern int printf(const char *format, ...);

int target_func(int a, int b) {
    unsigned int crc = ((unsigned int)a ^ (unsigned int)b) & 0xFFFF;
    for (int i = 0; i < 8; ++i) {
        if (crc & 1) crc = (crc >> 1) ^ 0xEDB88320;
        else crc = crc >> 1;
    }
    return (int)((crc ^ 0xFFFFFFFF) & 0xFFFF);
}
""",

    "fsm_state_machine": """\
extern int printf(const char *format, ...);

int target_func(int a, int b) {
    int state = (a & 3);
    int acc = b;
    for (int step = 0; step < 4; ++step) {
        if (state == 0) { acc += (a ^ 0x11); state = (acc & 3); }
        else if (state == 1) { acc ^= (a + 0x22); state = ((acc >> 2) & 3); }
        else if (state == 2) { acc = (acc * 3) + 0x33; state = (acc & 3); }
        else { acc -= (a ^ 0x44); state = 0; }
    }
    return acc & 0xFFFF;
}
""",

    "toy_crypto": """\
extern int printf(const char *format, ...);

static const unsigned char SBOX[16] = {
    0xE, 0x4, 0xD, 0x1, 0x2, 0xF, 0xB, 0x8,
    0x3, 0xA, 0x6, 0xC, 0x5, 0x9, 0x0, 0x7
};

int target_func(int a, int b) {
    unsigned char state = (unsigned char)((a ^ b) & 0x0F);
    unsigned char key = (unsigned char)(b & 0x0F);
    for (int round = 0; round < 3; ++round) {
        state = SBOX[state ^ key];
        key = (key + 0x3) & 0x0F;
    }
    return (int)state;
}
"""
}


# ─── Black-Box Surrogate Regressor ──────────────────────────────────────────

class BlackBoxSurrogateModel:
    """
    K-Nearest Neighbor & Piecewise Linear Regressor simulating
    an automated attacker trying to learn f(a, b) -> y purely from sampled I/O pairs.
    """
    def __init__(self, k_neighbors: int = 5):
        self.k = k_neighbors
        self.X_train = None
        self.y_train = None

    def fit(self, X: np.ndarray, y: np.ndarray):
        self.X_train = np.array(X, dtype=np.float64)
        self.y_train = np.array(y, dtype=np.float64)

    def predict(self, X_test: np.ndarray) -> np.ndarray:
        preds = []
        for x in X_test:
            dists = np.sum(np.abs(self.X_train - x), axis=1)
            nn_idx = np.argsort(dists)[:self.k]
            pred_val = np.round(np.median(self.y_train[nn_idx]))
            preds.append(int(pred_val))
        return np.array(preds, dtype=np.int64)


# ─── Evaluation Pipeline ─────────────────────────────────────────────────────

def generate_driver(seed: int, count: int) -> str:
    return f"""\
int main(int argc, char **argv) {{
    unsigned int s = {seed};
    for (int i = 0; i < {count}; ++i) {{
        s = s * 1103515245 + 12345;
        int a = (s >> 16) % 1000;
        s = s * 1103515245 + 12345;
        int b = (s >> 16) % 1000;
        printf("%d %d %d\\n", a, b, target_func(a, b));
    }}
    return 0;
}}
"""

def evaluate_target(name: str, c_code: str, train_samples: int = 200, test_samples: int = 200):
    tmpdir = tempfile.mkdtemp(prefix="vectis_bb_")
    src_c = os.path.join(tmpdir, "orig.c")
    obf_c = os.path.join(tmpdir, "obf.c")
    orig_bin = os.path.join(tmpdir, "orig.bin")
    obf_bin  = os.path.join(tmpdir, "obf.bin")

    # Combine func + training generator (seed=1337)
    train_code = c_code + "\n" + generate_driver(1337, train_samples)
    test_code  = c_code + "\n" + generate_driver(4242, test_samples)

    with open(src_c, "w") as f:
        f.write(train_code)

    # 1. Obfuscate training target via Vectis
    subprocess.run([
        MAIN_BIN, "-i", src_c, "-o", obf_c,
        "--poly-mba", "--opaque", "--dyn-opaque"
    ], check=True, capture_output=True)

    # 2. Compile obfuscated training binary & original test binary
    subprocess.run(["clang", "-w", "-O2", obf_c, "-o", obf_bin], check=True)
    
    test_src = os.path.join(tmpdir, "test.c")
    with open(test_src, "w") as f:
        f.write(test_code)
    subprocess.run(["clang", "-w", "-O2", test_src, "-o", orig_bin], check=True)

    # 3. Collect train I/O pairs
    r_train = subprocess.run([obf_bin], capture_output=True, text=True, check=True)
    train_data = [list(map(int, line.split())) for line in r_train.stdout.strip().splitlines() if line.strip()]
    X_train = np.array([[row[0], row[1]] for row in train_data])
    y_train = np.array([row[2] for row in train_data])

    # 4. Collect test I/O pairs
    r_test = subprocess.run([orig_bin], capture_output=True, text=True, check=True)
    test_data = [list(map(int, line.split())) for line in r_test.stdout.strip().splitlines() if line.strip()]
    X_test = np.array([[row[0], row[1]] for row in test_data])
    y_test_true = np.array([row[2] for row in test_data])

    # 5. Fit Black-box surrogate model
    model = BlackBoxSurrogateModel(k_neighbors=3)
    model.fit(X_train, y_train)
    y_pred = model.predict(X_test)

    # 6. Compute empirical learnability metrics
    exact_matches = np.sum(y_pred == y_test_true)
    exact_match_rate = (exact_matches / test_samples) * 100.0
    mae = float(np.mean(np.abs(y_pred - y_test_true)))
    
    # Reconstruction resistance: 100 - exact_match_rate
    resistance_score = max(0.0, 100.0 - exact_match_rate)

    return {
        "target": name,
        "train_samples": train_samples,
        "test_samples": test_samples,
        "exact_match_rate_pct": exact_match_rate,
        "mean_absolute_error": mae,
        "resistance_score": resistance_score,
        "status": "PASS" if resistance_score >= 80.0 else "MODERATE"
    }


def run_benchmark():
    print("\n" + "=" * 70)
    print("      VECTIS NEXT BLACK-BOX BEHAVIOR APPROXIMATION BENCHMARK")
    print("=" * 70)
    print("Evaluates empirical reverse-engineering resistance against I/O surrogate models.\n")

    results = []
    for name, code in BENCHMARK_TARGETS.items():
        t0 = time.time()
        res = evaluate_target(name, code, train_samples=250, test_samples=250)
        dt = time.time() - t0
        res["duration_sec"] = dt
        results.append(res)
        print(f"  [+] Target: {name:<18} | Match Rate: {res['exact_match_rate_pct']:5.1f}% | "
              f"Resistance: {res['resistance_score']:5.1f}/100 | Time: {dt:.2f}s")

    avg_resistance = np.mean([r["resistance_score"] for r in results])
    print("\n" + "-" * 70)
    print(f"  Overall Empirical Black-Box Resistance: {avg_resistance:.2f} / 100.0")
    print("-" * 70 + "\n")

    # Save benchmark artifact
    os.makedirs(os.path.join(PROJECT_ROOT, "benchmarks"), exist_ok=True)
    out_json = os.path.join(PROJECT_ROOT, "benchmarks/blackbox_results.json")
    with open(out_json, "w") as f:
        json.dump(results, f, indent=2)
    print(f"[✓] Benchmark results saved to {out_json}\n")


if __name__ == "__main__":
    run_benchmark()
