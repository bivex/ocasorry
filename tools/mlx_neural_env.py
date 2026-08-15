#!/usr/bin/env python3
"""
mlx_neural_env.py — 64-Bit Z3 SMT Formal Verification Environment for Neural VCPU Synthesis.
Provides strict mathematical verification (unsat = sound, sat/unknown = penalty) and AST feature extraction.
"""

import time
import numpy as np
import z3

# Actions that genuinely mutate the Z3 AST (real obfuscation).
# DECOY/ROTATION emit C code but don't change current_expr — they must NOT earn reward.
REAL_MBA_ACTIONS = frozenset({
    "MBA_DECOMP_ADD",
    "MBA_DECOMP_SUB",
    "MBA_AFFINE_XOR",
    "MBA_DEMORGAN_OR",
    "QUADRATIC_INVARIANT",
    "AFFINE_SBOX_ENTANGLE",
})


def extract_ast_features(expr):
    """Robust non-textual AST feature extractor via Z3 node kind inspection.
    Uses iterative BFS + visited-set to avoid RecursionError on deep trees."""
    counts = {"add": 0, "sub": 0, "xor": 0, "and": 0, "or": 0, "mul": 0, "shift": 0}
    max_depth = 0
    stack = [(expr, 1)]
    visited = set()

    while stack:
        node, depth = stack.pop()
        max_depth = max(max_depth, depth)
        if not z3.is_ast(node) or node.get_id() in visited:
            continue
        visited.add(node.get_id())

        try:
            decl = node.decl()
            kind = decl.kind() if decl is not None else None
            if   kind == z3.Z3_OP_BADD:  counts["add"] += 1
            elif kind == z3.Z3_OP_BSUB:  counts["sub"] += 1
            elif kind == z3.Z3_OP_BXOR:  counts["xor"] += 1
            elif kind == z3.Z3_OP_BAND:  counts["and"] += 1
            elif kind == z3.Z3_OP_BOR:   counts["or"]  += 1
            elif kind == z3.Z3_OP_BMUL:  counts["mul"] += 1
            elif kind in (z3.Z3_OP_BSHL, z3.Z3_OP_BLSHR, z3.Z3_OP_BASHR):
                counts["shift"] += 1
        except Exception:
            pass

        for child in node.children():
            stack.append((child, depth + 1))

    return counts, max_depth


class SMTAttackEnv:
    """
    64-Bit Formal Verification & SMT Attack Simulation Environment.

    Strict SMT result handling:
      unsat   → semantically proven equivalent → reward (positive)
      sat     → counterexample found (bug)     → reward = -100, done
      unknown → solver timed out (unproven)    → reward = -50,  done

    DECOY/ROTATION actions do NOT mutate current_expr.  They always produce
    unsat (trivially, orig == current), but earn ZERO reward to prevent the
    policy from learning to emit no-op obfuscation.
    """

    ACTION_NAMES = [
        "MBA_DECOMP_ADD",        # x + y  <=> (x ^ y)  + 2*(x & y)
        "MBA_DECOMP_SUB",        # x - y  <=> (x ^ y)  - 2*(~x & y)  [valid only step-1]
        "MBA_AFFINE_XOR",        # x ^ y  <=> (x | y)  - (x & y)
        "MBA_DEMORGAN_OR",       # x | y  <=> (x ^ y)  + (x & y)
        "QUADRATIC_INVARIANT",   # (a*(a+1)) & 1 == 0  -> zero invariant xor
        "AFFINE_SBOX_ENTANGLE",  # reversible affine layer in Z_{2^64}
        "DECOY_JUMP_GUARD",      # C-only: accumulator churn (no AST change)
        "REGISTER_ROTATION_SEED" # C-only: VREG rotation comment (no AST change)
    ]

    # 64-bit affine constants verified: K1 * INV_K1 ≡ 1 (mod 2^64)
    K1_64    = 0x9E3779B97F4A7C15
    INV_K1_64 = 0xF1DE83E19937733D
    K2_64    = 0x517CC1B727220A95

    def __init__(self, bit_width: int = 64):
        self.bit_width = bit_width
        self.reset()

    def reset(self, target_op: str = "ADD"):
        self.target_op = target_op
        self.a_sym = z3.BitVec('a', self.bit_width)
        self.b_sym = z3.BitVec('b', self.bit_width)

        op_map = {
            "ADD": self.a_sym + self.b_sym,
            "SUB": self.a_sym - self.b_sym,
            "XOR": self.a_sym ^ self.b_sym,
            "OR":  self.a_sym | self.b_sym,
            "AND": self.a_sym & self.b_sym,
        }
        self.orig_expr = op_map.get(target_op, self.a_sym + self.b_sym)
        self.current_expr = self.orig_expr

        self.c_code_steps: list[tuple[str, str]] = []
        self.history: list[str] = []
        self.steps = 0
        return self.get_state()

    def get_state(self) -> np.ndarray:
        """12-dimensional numerical feature tensor extracted structurally from the Z3 AST."""
        counts, depth = extract_ast_features(self.current_expr)
        size = self.current_expr.size()
        return np.array([
            float(self.steps) / 6.0,
            float(size) / 40.0,
            float(depth) / 12.0,
            float(counts["add"])   / 10.0,
            float(counts["sub"])   / 10.0,
            float(counts["xor"])   / 10.0,
            float(counts["and"])   / 10.0,
            float(counts["or"])    / 10.0,
            float(counts["mul"])   / 10.0,
            float(len(self.history)) / 6.0,
            1.0 if self.target_op == "ADD" else 0.0,
            1.0 if self.target_op == "XOR" else 0.0,
        ], dtype=np.float32)

    def step(self, action_idx: int):
        self.steps += 1
        action = self.ACTION_NAMES[action_idx]
        self.history.append(action)
        a, b = self.a_sym, self.b_sym
        is_decoy = action not in REAL_MBA_ACTIONS   # no AST mutation

        if action == "MBA_DECOMP_ADD":
            self.current_expr = (self.current_expr ^ b) + ((self.current_expr & b) << 1) - b
            self.c_code_steps.append(("MBA_DECOMP_ADD",
                "__cur = (__cur ^ __b) + ((__cur & __b) << 1ULL) - __b;"))
        elif action == "MBA_DECOMP_SUB":
            # Identity holds when current_expr ≡ a (first step only).
            # On later steps the Z3 proof is still sound, but the semantic
            # label "SUB decomposition" is misleading — tracked in comments.
            self.current_expr = (self.current_expr ^ b) - ((~self.current_expr & b) << 1) + b
            self.c_code_steps.append(("MBA_DECOMP_SUB",
                "__cur = (__cur ^ __b) - ((~__cur & __b) << 1ULL) + __b;"))
        elif action == "MBA_AFFINE_XOR":
            self.current_expr = (self.current_expr | b) - (self.current_expr & b) - b + (a ^ b)
            self.c_code_steps.append(("MBA_AFFINE_XOR",
                "__cur = ((__cur | __b) - (__cur & __b)) - __b + (__a ^ __b);"))
        elif action == "MBA_DEMORGAN_OR":
            self.current_expr = (self.current_expr ^ b) + (self.current_expr & b) - b
            self.c_code_steps.append(("MBA_DEMORGAN_OR",
                "__cur = (__cur ^ __b) + (__cur & __b) - __b;"))
        elif action == "QUADRATIC_INVARIANT":
            # (a*(a+1)) is always even in Z_{2^n} → bit-0 is zero → safe xor identity
            inv = (a * (a + 1)) & 1
            self.current_expr = self.current_expr ^ inv
            self.c_code_steps.append(("QUADRATIC_INVARIANT",
                "__cur ^= ((__a * (__a + 1ULL)) & 1ULL);"))
        elif action == "AFFINE_SBOX_ENTANGLE":
            k1    = z3.BitVecVal(self.K1_64,    self.bit_width)
            inv_k1 = z3.BitVecVal(self.INV_K1_64, self.bit_width)
            k2    = z3.BitVecVal(self.K2_64,    self.bit_width)
            self.current_expr = (((self.current_expr + k2) * k1) * inv_k1) - k2
            self.c_code_steps.append(("AFFINE_SBOX_ENTANGLE",
                f"__cur = (((__cur + 0x{self.K2_64:016X}ULL) * 0x{self.K1_64:016X}ULL)"
                f" * 0x{self.INV_K1_64:016X}ULL) - 0x{self.K2_64:016X}ULL;"))
        elif action == "DECOY_JUMP_GUARD":
            # C-only side-effect; no AST mutation → always earns zero reward.
            self.c_code_steps.append(("DECOY_JUMP_GUARD",
                "__vm_state_acc = (__vm_state_acc * 0x63c63cd93839c9b9ULL)"
                " ^ 0x517CC1B727220A95ULL;"))
        elif action == "REGISTER_ROTATION_SEED":
            self.c_code_steps.append(("REGISTER_ROTATION_SEED",
                "/* VREG rotation seed shift */"))

        # ── Strict 3-way SMT check ────────────────────────────────────────────
        solver = z3.Tactic('qfbv').solver()
        solver.set("timeout", 300)  # 300 ms
        solver.add(self.orig_expr != self.current_expr)

        t0  = time.perf_counter()
        res = solver.check()
        solve_duration = time.perf_counter() - t0
        done = self.steps >= 5

        if res == z3.unsat:
            is_valid = True
            if is_decoy:
                # DECOY trivially passes (orig == current) → zero reward,
                # prevents policy from gaming the verifier with no-ops.
                reward = 0.0
            else:
                counts, depth = extract_ast_features(self.current_expr)
                reward = (solve_duration * 1000.0) + (self.current_expr.size() * 0.15) + (depth * 0.3)
        elif res == z3.sat:
            # Counterexample: semantic bug — hard penalty, abort episode.
            is_valid, reward, done = False, -100.0, True
        else:
            # unknown/timeout: unproven — cannot claim equivalence.
            is_valid, reward, done = False, -50.0, True

        return self.get_state(), reward, done, {
            "valid": is_valid,
            "status": str(res),
            "z3_time": solve_duration,
            "is_decoy": is_decoy,
        }
