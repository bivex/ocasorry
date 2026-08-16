(** Domain Service: C11 Runtime Kernel, Register Bank Matrix and CFI State Emitter
    Each build session generates a fresh [var_set] with unique C identifier suffixes,
    randomised stack sizes, and randomised multiplicative constants.  This ensures
    that every compilation produces structurally distinct machine code, increasing
    binary diversity across builds without altering program semantics. *)

(* ── Per-session name/constant bundle ──────────────────────────────────────── *)

let rand_hex4 () = Printf.sprintf "%04x" (Random.int 0xFFFF)

type var_set = {
  vsd      : string;   (* vstack_data array name    *)
  vsc      : string;   (* vstack_ctrl array name    *)
  vpd      : string;   (* vsp_d counter name        *)
  vpc      : string;   (* vsp_c counter name        *)
  vma      : string;   (* vm_state_acc name         *)
  te       : string;   (* t_entry timer name        *)
  cfi      : string;   (* cfi_canary name           *)
  pc       : string;   (* program counter           *)
  rw       : string;   (* raw instruction word      *)
  ky       : string;   (* rolling key               *)
  ins      : string;   (* decoded instruction       *)
  f6       : string;   (* funct6 field              *)
  vm       : string;   (* vm flag field             *)
  vs2      : string;   (* vs2 field                 *)
  vs1      : string;   (* vs1 field                 *)
  f3       : string;   (* funct3 field              *)
  vd       : string;   (* vd field                  *)
  vbl      : string;   (* vbc_live scratchpad name  *)
  vbm      : string;   (* vbc_mutation_round name   *)
  fae      : string;   (* fn_addr_entropy name      *)

  alloc_fn : string;   (* ephemeral alloc helper    *)
  free_fn  : string;   (* ephemeral free helper     *)
  dss      : int;      (* data stack size 48..95    *)
  css      : int;      (* ctrl stack size 24..47    *)
  stk_a_d  : int;      (* data stack coprime multiplier *)
  stk_b_d  : int;      (* data stack offset             *)
  stk_a_c  : int;      (* ctrl stack coprime multiplier *)
  stk_b_c  : int;      (* ctrl stack offset             *)
  gold1    : int64;    (* random odd multiplier 1   *)
  gold2    : int64;    (* random odd multiplier 2   *)
}

let rec find_coprime m =
  let a = (Random.int 63) * 2 + 1 in
  let rec gcd x y = if y = 0 then x else gcd y (x mod y) in
  if gcd a m = 1 then a else find_coprime m

let make_var_set () : var_set =
  let s () = rand_hex4 () ^ rand_hex4 () in
  (* random odd 64-bit integer — safe replacement for fixed golden-ratio consts *)
  let rand_odd () =
    let v = Random.int64 Int64.max_int in
    Int64.logor v 1L
  in
  let dss_val = 48 + (Random.int 48) in
  let css_val = 24 + (Random.int 24) in
  {
    vsd      = "__vsd_"  ^ s ();
    vsc      = "__vsc_"  ^ s ();
    vpd      = "__vpd_"  ^ s ();
    vpc      = "__vpc_"  ^ s ();
    vma      = "__vma_"  ^ s ();
    te       = "__te_"   ^ s ();
    cfi      = "__cfi_"  ^ s ();
    pc       = "__pc_"   ^ s ();
    rw       = "__rw_"   ^ s ();
    ky       = "__ky_"   ^ s ();
    ins      = "__in_"   ^ s ();
    f6       = "__f6_"   ^ s ();
    vm       = "__vm_"   ^ s ();
    vs2      = "__vs2_"  ^ s ();
    vs1      = "__vs1_"  ^ s ();
    f3       = "__f3_"   ^ s ();
    vd       = "__vd_"   ^ s ();
    vbl      = "__vbl_"  ^ s ();
    vbm      = "__vbm_"  ^ s ();
    fae      = "__fae_"  ^ s ();

    alloc_fn = "__vma_"  ^ s ();
    free_fn  = "__vmf_"  ^ s ();
    dss      = dss_val;
    css      = css_val;
    stk_a_d  = find_coprime dss_val;
    stk_b_d  = Random.int dss_val;
    stk_a_c  = find_coprime css_val;
    stk_b_c  = Random.int css_val;
    gold1    = rand_odd ();
    gold2    = rand_odd ();
  }



(* ── Public emitters ────────────────────────────────────────────────────────── *)

let rand_prologue_jitter () =
  let aarch64_insns = [|
    "nop";
    "hint #0";
    "yield";
    "add sp, sp, #0";
    "sub sp, sp, #0";
    "orr x16, x16, x16";
    "eor x17, x17, xzr";
  |] in
  let n = 2 + Random.int 4 in
  let chosen_aarch64 = List.init n (fun _ -> aarch64_insns.(Random.int (Array.length aarch64_insns))) in
  let aarch64_str = String.concat "\\n\\t" chosen_aarch64 in
  let x86_insns = [| "nop"; "pause"; "lea rsp, [rsp+0]"; "mov rax, rax"; "xor r11, 0" |] in
  let chosen_x86 = List.init n (fun _ -> x86_insns.(Random.int (Array.length x86_insns))) in
  let x86_str = String.concat "\\n\\t" chosen_x86 in
  Printf.sprintf {|
    /* Architectural Prologue Jitter & Diversity Sled */
    #if defined(__aarch64__) || defined(__arm64__)
    __asm__ volatile("%s" : : : "memory");
    #elif defined(__x86_64__)
    __asm__ volatile("%s" : : : "memory");
    #endif
|} aarch64_str x86_str


let emit_header
    ~(vs : var_set)
    ~(ret_type_str : string)
    ~(fn_name : string)
    ~(fn_params : string)
    ~(sbox_code : string) : string =
  let w1 = Random.int 256 in
  let w2 = Random.int 256 in
  let w3 = Random.int 256 in
  let dcv = rand_hex4 () in
  let dval = Random.int64 Int64.max_int in
  let jitter_alloc = rand_prologue_jitter () in
  let jitter_free  = rand_prologue_jitter () in
  let jitter_fn    = rand_prologue_jitter () in
  Printf.sprintf {|
#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE
#endif
#include <sys/mman.h>
#include <unistd.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#ifdef __APPLE__
#include <pthread.h>
#include <libkern/OSCacheControl.h>
#endif

__attribute__((noinline))
static void *%s(size_t *out_sz, size_t min_sz) {
%s
    volatile unsigned long long __dcv_%s = 0x%LxULL;
    (void)__dcv_%s;
    size_t page_sz = (size_t)sysconf(_SC_PAGESIZE);
    if (page_sz < 4096) page_sz = 4096;
    size_t alloc_sz = (min_sz + page_sz - 1) & ~(page_sz - 1);
    *out_sz = alloc_sz;
#if defined(__APPLE__) && (defined(__aarch64__) || defined(__arm64__))
    void *ptr = mmap(NULL, alloc_sz, PROT_READ | PROT_WRITE | PROT_EXEC,
                     MAP_ANON | MAP_PRIVATE | MAP_JIT, -1, 0);
#elif defined(__aarch64__) || defined(__arm64__)
    void *ptr = mmap(NULL, alloc_sz, PROT_READ | PROT_WRITE | PROT_EXEC,
                     MAP_ANON | MAP_PRIVATE, -1, 0);
#else
    void *ptr = mmap(NULL, alloc_sz, PROT_READ | PROT_WRITE,
                     MAP_ANON | MAP_PRIVATE, -1, 0);
#endif
    if (ptr == MAP_FAILED) return NULL;
    return ptr;
}

__attribute__((noinline))
static void %s(void *ptr, size_t sz) {
%s
    if (ptr && ptr != MAP_FAILED) {
#if defined(__APPLE__) && (defined(__aarch64__) || defined(__arm64__))
        pthread_jit_write_protect_np(0);
#endif
        memset(ptr, 0x%02x, sz);
        memset(ptr, 0x%02x, sz);
        memset(ptr, 0x%02x, sz);
        munmap(ptr, sz);
    }
}

__attribute__((visibility("default")))
%s %s(%s) {
%s
%s|} vs.alloc_fn jitter_alloc dcv dval dcv vs.free_fn jitter_free w1 w2 w3 ret_type_str fn_name fn_params jitter_fn sbox_code

let emit_vbank
    ~(vs : var_set)
    ~(vreg_total : int)
    ~(vreg_rot_seed : int)
    ~(reg_mask_base : int64)
    ~(reg_mask_step : int64) : string =
  ignore vs;
  let mult = (Random.int 15) * 2 + 1 in
  let off  = if vreg_total > 0 then Random.int vreg_total else 0 in
  let clobber = rand_prologue_jitter () in
  Printf.sprintf {|
    /* Anti-VTIL / Anti-NoVmp: Overlapping Aliased VCPU Register Matrix & Dynamic Register Cycling (Gap 2) */
    union __attribute__((aligned(16))) {
        unsigned char __b[1024];
        unsigned long long __q[%d];
    } __vbank;
    #define __VREG_ROT(r) (((unsigned int)(r) + %uU) & 0x3FU)
    #define __VREG_MASK(r) (0x%LxULL + ((unsigned long long)__VREG_ROT(r) * 0x%LxULL))
    #define __VREG_GET(r) (__vbank.__q[__VREG_ROT(r)] ^ __VREG_MASK(r))
    #define __VREG_SET(r, val) do { __vbank.__q[__VREG_ROT(r)] = ((unsigned long long)(val)) ^ __VREG_MASK(r); } while(0)

    for (int __i = 0; __i < %d; __i++) {
        unsigned int __v_idx = (((unsigned int)__i * %uU) + %uU) %% %uU;
        __vbank.__q[__v_idx] = (0x%LxULL + ((unsigned long long)__v_idx * 0x%LxULL));
    }
%s
|} vreg_total vreg_rot_seed reg_mask_base reg_mask_step
   vreg_total mult off vreg_total reg_mask_base reg_mask_step clobber


let emit_shadow_and_cfi
    ~(vs : var_set)
    ~(word_count : int)
    ~(vbc_name : string)
    ~(ptr_arg : string)
    ~(reg_mask_base : int64)
    ~(reg_mask_step : int64)
    ~(arg_inits : string) : string =
  let cfi_seed = Int64.logand (Int64.abs reg_mask_base) 0xFFFFFFFFFFFFL in
  let cfi_xor  = Int64.logxor reg_mask_step 0xDEADBEEFCAFEBABEL in
  let hash_idx = if word_count > 1 then 1 else 0 in
  (* per-build decoy tag so even the decoy line differs *)
  let dtag = rand_hex4 () ^ rand_hex4 () in
  let decoy_val = Random.int64 Int64.max_int in
  Printf.sprintf {|
    /* Vector 2: Dual Shadow Stack (%s + %s) with Algebraic Scrambling */
    #define __VSTK_PHYS_D(idx) ((((unsigned int)(idx)) * %uU + %uU) %% %uU)
    #define __VSTK_PHYS_C(idx) ((((unsigned int)(idx)) * %uU + %uU) %% %uU)

    unsigned long long %s[%d] = {0};
    unsigned long long %s[%d] = {0};
    unsigned int %s = 0;
    unsigned int %s = 0;
    unsigned long long %s = 0x%LxULL;
    volatile unsigned long long __dcv_%s = 0x%LxULL ^ (unsigned long long)(uintptr_t)&%s[0];
    (void)__dcv_%s;

    /* Vector 12: Microarchitectural Timer Sampling & Anti-Single-Stepping */
    #if defined(__aarch64__)
    unsigned long long %s;
    __asm__ volatile("mrs %%0, cntvct_el0" : "=r"(%s));
    #elif defined(__x86_64__)
    unsigned int __t_lo, __t_hi;
    __asm__ volatile("rdtsc" : "=a"(__t_lo), "=d"(__t_hi));
    unsigned long long %s = ((unsigned long long)__t_hi << 32) | __t_lo;
    #else
    unsigned long long %s = 0;
    #endif

    /* Vector 8: Ephemeral Self-Scrubbing Bytecode Scratchpad & Metamorphic Mutation Array */
    unsigned int %s[%d];
    memcpy(%s, %s, sizeof(%s));
    unsigned int %s[%d] = {0};

    const unsigned long long %s =
        (unsigned long long)(uintptr_t)(%s != 0 ? (const void *)%s : (const void *)&%s);
    const unsigned long long __vbc_hash_0 = %s[0] ^ (unsigned long long)%s[%d];
    const unsigned long long %s =
        0x%LxULL
        ^ (%s * 0x%LxULL)
        ^ (__vbc_hash_0 * 0x%LxULL);

    %s[__VSTK_PHYS_C(%s++)] = %s ^ 0x%LxULL;

%s
    unsigned int %s = 0;
    unsigned int %s, %s, %s;
    unsigned char %s, %s, %s, %s, %s, %s;
|}
  (* vstack names & permutation keys *)
  vs.vsd vs.vsc
  vs.stk_a_d vs.stk_b_d vs.dss
  vs.stk_a_c vs.stk_b_c vs.css
  vs.vsd vs.dss
  vs.vsc vs.css
  vs.vpd
  vs.vpc
  vs.vma vs.gold1
  (* decoy *)
  dtag decoy_val vs.vsd dtag
  (* timer *)
  vs.te vs.te vs.te vs.te
  (* bytecode scratchpad *)
  vs.vbl word_count vs.vbl vbc_name vs.vbl vs.vbm word_count
  (* fn entropy *)
  vs.fae ptr_arg ptr_arg vs.vbl
  (* hash + canary *)
  vs.vbl vs.vbl hash_idx
  vs.cfi
  cfi_seed
  vs.fae vs.gold1
  vs.gold2
  (* push canary *)
  vs.vsc vs.vpc vs.cfi cfi_xor
  (* arg inits *)
  arg_inits
  (* register aliases *)
  vs.pc
  vs.rw vs.ky vs.ins
  vs.f6 vs.vm vs.vs2 vs.vs1 vs.f3 vs.vd

let emit_epilogue
    ~(vs : var_set)
    ~(out_reg : int)
    ~(ret_type_str : string)
    ~(reg_mask_step : int64) : string =
  let cfi_xor = Int64.logxor reg_mask_step 0xDEADBEEFCAFEBABEL in
  let stepped_magic = Int64.logor (Random.int64 Int64.max_int) 1L in
  let poison_magic  = Int64.logor (Random.int64 Int64.max_int) 1L in
  let epilogue_jitter = rand_prologue_jitter () in
  Printf.sprintf {|
__h_vret: ;
    /* Verify Shadow Control Stack CFI Canary with Algebraic Scrambling */
    if (%s == 0 || ((%s[__VSTK_PHYS_C(--%s)] ^ 0x%LxULL) != %s)) {
        __builtin_trap();
    }
    /* Vector 12: Microarchitectural Timer Check & Silent State Poisoning */
    #if defined(__aarch64__)
    unsigned long long __t_exit;
    __asm__ volatile("mrs %%0, cntvct_el0" : "=r"(__t_exit));
    #elif defined(__x86_64__)
    unsigned int __x_lo, __x_hi;
    __asm__ volatile("rdtsc" : "=a"(__x_lo), "=d"(__x_hi));
    unsigned long long __t_exit = ((unsigned long long)__x_hi << 32) | __x_lo;
    #else
    unsigned long long __t_exit = 0;
    #endif
    unsigned long long __t_delta = (__t_exit > %s) ? (__t_exit - %s) : 0ULL;
    unsigned long long __stepped = (__t_delta > 1000000000ULL) ? 1ULL : 0ULL;
    %s ^= (__stepped * 0x%LxULL);

    /* Vector 11: Anti-Symbolic Quadratic Invariant & Dataflow Interlock */
    if (((%s * (%s + 1ULL)) & 1ULL) != 0ULL) {
        __builtin_trap();
    }
    unsigned long long __res_val = (__VREG_GET(%d) ^ (__stepped * 0x%LxULL)) ^ ((%s * (%s + 1ULL)) & 1ULL);

    /* Volatile Scrubbing with Compiler Memory Barriers (Prevents Clang -O2/-O3 DSE) */
    volatile unsigned char *__wp_vb = (volatile unsigned char *)&__vbank;
    for (size_t __i = 0; __i < sizeof(__vbank); ++__i) __wp_vb[__i] = 0;
    volatile unsigned char *__wp_vbl = (volatile unsigned char *)%s;
    for (size_t __i = 0; __i < sizeof(%s); ++__i) __wp_vbl[__i] = 0;
    volatile unsigned char *__wp_vbm = (volatile unsigned char *)%s;
    for (size_t __i = 0; __i < sizeof(%s); ++__i) __wp_vbm[__i] = 0;
    volatile unsigned char *__wp_vsd = (volatile unsigned char *)%s;
    for (size_t __i = 0; __i < sizeof(%s); ++__i) __wp_vsd[__i] = 0;
    volatile unsigned char *__wp_vsc = (volatile unsigned char *)%s;
    for (size_t __i = 0; __i < sizeof(%s); ++__i) __wp_vsc[__i] = 0;
    __asm__ volatile("" : : "r"(__wp_vb), "r"(__wp_vbl), "r"(__wp_vbm), "r"(__wp_vsd), "r"(__wp_vsc) : "memory");
%s
    return (%s)__res_val;
}
#undef __VSTK_PHYS_D
#undef __VSTK_PHYS_C
#undef __VREG_ROT
#undef __VREG_MASK
#undef __VREG_GET
#undef __VREG_SET
#undef __VISA_DISPATCH
|}
  vs.vpc vs.vsc vs.vpc cfi_xor vs.cfi
  vs.te vs.te
  vs.vma poison_magic
  vs.vma vs.vma
  out_reg stepped_magic vs.vma vs.vma
  vs.vbl vs.vbl
  vs.vbm vs.vbm
  vs.vsd vs.vsd
  vs.vsc vs.vsc
  epilogue_jitter
  ret_type_str







(* Expose a field accessor needed by dispatch emitter — kept as a module-level record *)
let field_names (vs : var_set) = vs
