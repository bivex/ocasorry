; ==============================================================================
; VECTIS FORMALLY VERIFIED POLYMORPHIC COMPILATION PROOF CERTIFICATE (Z3 / QF_BV)
; Target Function : compute_hot_loop
; Bit Width       : 64 bits
; Generated Time  : 2026-08-16 19:22:58 UTC
; Mathematical Property: ∀ (a, b, K_epoch) ∈ BV64: f_obf ≡ f_orig (SOUNDNESS)
; Independent Verification: (check-sat) MUST return 'unsat'
; ==============================================================================

; benchmark generated from python API
(set-info :status unknown)
(declare-fun k_epoch_0 () (_ BitVec 64))
(declare-fun arg_a () (_ BitVec 64))
(declare-fun arg_b () (_ BitVec 64))
(assert
 (let ((?x19 (bvadd (bvadd (bvxor arg_a arg_b) (bvshl (bvand arg_a arg_b) (_ bv1 64))) (bvshl arg_a (_ bv1 64)))))
(let ((?x24 (bvxor (bvadd ?x19 arg_a) (bvand (bvmul arg_a (bvadd arg_a (_ bv1 64))) (_ bv1 64)))))
(let ((?x30 (bvmul (bvxor (bvxor (bvmul ?x24 (_ bv6364136223846793005 64)) k_epoch_0) k_epoch_0) (_ bv13877824140714322085 64))))
(let ((?x12 (bvadd (bvadd arg_a arg_b) (bvmul arg_a (_ bv3 64)))))
(and (distinct ?x12 ?x30) true))))))
(check-sat)
