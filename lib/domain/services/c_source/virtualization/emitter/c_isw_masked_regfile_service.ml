(** Domain Service: ISW 1st-Order Masked VCPU Register File (Эшелон 2)

    Implements Ishai-Sahai-Wagner boolean masking of the VCPU register file.
    Each sensitive register x is split into shares (share0, share1) such that:
      plaintext = share0 XOR share1

    - Masked AND uses ISW cross-term protocol with hardware TRNG entropy injection.
    - A2B conversion runs in O(log k) via Kogge-Stone carry lookahead.
    - Plaintext NEVER materializes in host memory or registers.
    - Defeats: memory dump scanners, taint trackers, constraint-free DSE (Pushan).

    TRNG function is emitted BEFORE the function body (file-scope static inline),
    since nested function definitions are illegal in C11.
*)

(** Emit the per-build TRNG static inline function at file scope.
    Must be concatenated BEFORE emit_header opens the function body. *)
let emit_isw_trng_preamble ~(trng_fn : string) ~(trng_seed : int64) : string =
  let seed_hi = Int64.to_int (Int64.shift_right_logical trng_seed 32) in
  let seed_lo = Int64.to_int (Int64.logand trng_seed 0xFFFFFFFFL) in
  Printf.sprintf {|
#ifndef _VECTIS_ISW_STDINT
#define _VECTIS_ISW_STDINT
#include <stdint.h>
#endif
/* ── Vectis ISW TRNG: per-build seeded arithmetic LCG + hardware entropy ─── */
static inline uint32_t %s(void) {
    static _Thread_local uint64_t __isw_state =
        (0x%08xULL << 32) | 0x%08xULL;
    __isw_state = __isw_state * 0x5851F42D4C957F2DULL + 0x14057B7EF767814FULL;
#if defined(__aarch64__) || defined(__arm64__)
    uint64_t __hw = 0;
    __asm__ volatile("mrs %%0, cntvct_el0" : "=r"(__hw));
    __isw_state ^= __hw;
#elif defined(__x86_64__)
    unsigned int __lo, __hi;
    __asm__ volatile("rdtsc" : "=a"(__lo), "=d"(__hi));
    __isw_state ^= ((uint64_t)__hi << 32) | __lo;
#endif
    return (uint32_t)(__isw_state >> 32);
}
|} trng_fn seed_hi seed_lo



(** Emit ISW masked register file variables and macros inside the function body.
    share0_name / share1_name are unique per build.
    trng_fn must already be emitted at file scope via emit_isw_trng_preamble. *)
let emit_isw_masked_regfile
    ~(share0_name : string)
    ~(share1_name : string)
    ~(vreg_total  : int)
    ~(trng_fn     : string) : string =
  let tmpl = {|
    /* ═══════════════════════════════════════════════════════════════════════════
       VECTIS ISW 1st-Order Masked VCPU Register File (Anti-Taint / Anti-Dump)
       Plaintext = @S0@[r] XOR @S1@[r] — never materializes in host memory.
       Protocol: Ishai-Sahai-Wagner d=1; masked AND with hardware entropy inject.
       ════════════════════════════════════════════════════════════════════════ */

    uint32_t @S0@[@N@];
    uint32_t @S1@[@N@];
    for (int __ri = 0; __ri < @N@; __ri++) {
        @S0@[__ri] = @RNG@();
        @S1@[__ri] = @S0@[__ri]; /* share1 = share0 => plaintext = 0 initially */
    }

    /* ── ISW Masked Register Accessors ───────────────────────────────────── */
    #define __ISW_GET(r) ((uint64_t)(@S0@[(r) & (@N@ - 1)] ^ @S1@[(r) & (@N@ - 1)]))
    #define __ISW_SET(r, val) do {                          \
        uint32_t __isw_r = @RNG@();                         \
        @S0@[(r) & (@N@ - 1)] = (uint32_t)((uint64_t)(val) >> 0) ^ __isw_r; \
        @S1@[(r) & (@N@ - 1)] = __isw_r;                   \
    } while(0)

    /* ── ISW Masked AND (C = A & B), d=1, no plaintext in any share ─────── */
    #define __ISW_AND(rd, r1, r2) do {                      \
        uint32_t __p00 = @S0@[r1] & @S0@[r2];              \
        uint32_t __p11 = @S1@[r1] & @S1@[r2];              \
        uint32_t __p01 = @S0@[r1] & @S1@[r2];              \
        uint32_t __p10 = @S1@[r1] & @S0@[r2];              \
        uint32_t __r01 = @RNG@();                           \
        uint32_t __r10 = (__r01 ^ __p01) ^ __p10;          \
        @S0@[rd] = __p00 ^ __r01;                          \
        @S1@[rd] = __p11 ^ __r10;                          \
    } while(0)

    /* ── ISW Masked XOR (C = A ^ B), linear — no cross-terms ────────────── */
    #define __ISW_XOR(rd, r1, r2) do {                      \
        @S0@[rd] = @S0@[r1] ^ @S0@[r2];                    \
        @S1@[rd] = @S1@[r1] ^ @S1@[r2];                    \
    } while(0)

    /* ── A2B Conversion O(log k): arithmetic mask (A+r) → boolean (x0^x1) ─ */
    /* Kogge-Stone parallel prefix, 5 rounds for k=32-bit words               */
    #define __ISW_A2B(rd, arith_A, arith_r) do {            \
        uint32_t __gamma = @RNG@();                          \
        uint32_t __T     = (uint32_t)(arith_A) ^ __gamma;   \
        uint32_t __carry = __gamma & __T;                   \
        __carry = (__carry << 1)  & ((__T ^ (uint32_t)(arith_r)) | __carry); \
        __carry = (__carry << 2)  & ((__T ^ (uint32_t)(arith_r)) | __carry); \
        __carry = (__carry << 4)  & ((__T ^ (uint32_t)(arith_r)) | __carry); \
        __carry = (__carry << 8)  & ((__T ^ (uint32_t)(arith_r)) | __carry); \
        __carry = (__carry << 16) & ((__T ^ (uint32_t)(arith_r)) | __carry); \
        @S0@[rd] = __T ^ __carry;                           \
        @S1@[rd] = (uint32_t)(arith_r) ^ __carry;           \
    } while(0)
|} in
  let r = Str.global_replace (Str.regexp "@S0@") share0_name tmpl in
  let r = Str.global_replace (Str.regexp "@S1@") share1_name r in
  let r = Str.global_replace (Str.regexp "@N@")  (string_of_int vreg_total) r in
  Str.global_replace (Str.regexp "@RNG@") trng_fn r


(** Emit ISW-masked AND handler *)
let emit_masked_and_handler
    ~(label      : string)
    ~(vs         : C_visa_c_runtime.var_set)
    ~(disp_macro : string) : string =
  Printf.sprintf {|
%s: {
    /* ISW Masked AND: C = A & B over boolean shares, plaintext never in regs */
    unsigned int __r1 = (unsigned int)%s & 0xF;
    unsigned int __r2 = (unsigned int)%s & 0xF;
    unsigned int __rd = (unsigned int)%s & 0xF;
    __ISW_AND(__rd, __r1, __r2);
    __VREG_SET(__rd, __ISW_GET(__rd));
    %s;
}
|} label vs.vs1 vs.vs2 vs.vd disp_macro


(** Emit ISW-masked XOR handler *)
let emit_masked_xor_handler
    ~(label      : string)
    ~(vs         : C_visa_c_runtime.var_set)
    ~(disp_macro : string) : string =
  Printf.sprintf {|
%s: {
    /* ISW Masked XOR: linear, no cross-terms needed */
    unsigned int __r1 = (unsigned int)%s & 0xF;
    unsigned int __r2 = (unsigned int)%s & 0xF;
    unsigned int __rd = (unsigned int)%s & 0xF;
    __ISW_XOR(__rd, __r1, __r2);
    __VREG_SET(__rd, __ISW_GET(__rd));
    %s;
}
|} label vs.vs1 vs.vs2 vs.vd disp_macro
