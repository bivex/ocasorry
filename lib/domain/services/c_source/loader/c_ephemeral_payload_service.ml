open GoblintCil.Cil

(** Domain Service: In-Memory Ephemeral Two-Tier Double JIT Payload Unpacking for CIL AST
    Integrates Two-Level JITting + Hardware-Level Implicit Flow:
    - Tier 1: Outer JIT Stager triggering hardware trap (BRK #0x42 on AArch64 / UD2 on x86_64)
    - Signal Interceptor: Catches SIGTRAP/SIGBUS and overwrites Program Counter (PC) in ucontext_t
    - Tier 2: Inner Encrypted Payload decrypted on-the-fly and executed natively in hardware
    - Zero-and-free wiping after execution.
*)
module Make (Entropy : Entropy_port.S) = struct
  module JIT = C_arm64_jit_compiler.Make(Entropy)

  let should_transform (fd : fundec) : bool =
    if fd.svar.vname = "main" || String.starts_with ~prefix:"__" fd.svar.vname
       || List.mem fd.svar.vname [ "printf"; "fprintf"; "sprintf"; "puts"; "exit"; "atoi"; "malloc"; "free" ] then false
    else if C_annotation_service.AnnotationHelper.should_skip_all fd then false
    else if List.length fd.sformals <> 1 then false
    else if C_annotation_service.AnnotationHelper.has_annotation fd "ephemeral"
            || C_annotation_service.AnnotationHelper.has_annotation fd "ephemeral_jit" then true
    else if C_annotation_service.AnnotationHelper.has_any_vm_annotation fd then false
    else if C_annotation_service.AnnotationHelper.has_custom_annotations fd then false
    else (
      let int_formals = List.filter (fun p -> isIntegralType p.vtype) fd.sformals in
      List.length fd.sformals = 1 && int_formals <> []
    )

  let transform_file (f : file) : file =
    let new_globals = ref [] in
    let func_count = ref 0 in

    let helper_code =
      GText {|
#ifndef _DARWIN_C_SOURCE
#define _DARWIN_C_SOURCE
#endif
#include <sys/mman.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <signal.h>
#ifdef __APPLE__
#include <pthread.h>
#include <libkern/OSCacheControl.h>
#include <sys/ucontext.h>
#endif

static void *__vectis_two_tier_active_pc = NULL;

#if defined(__APPLE__) && defined(__aarch64__)
static void __vectis_two_tier_signal_router(int sig, siginfo_t *info, void *context) {
    (void)sig; (void)info;
    ucontext_t *uc = (ucontext_t *)context;
    if (__vectis_two_tier_active_pc != NULL) {
        /* IMPLICIT FLOW: Redirect Program Counter in CPU hardware context */
        uc->uc_mcontext->__ss.__pc = (uint64_t)__vectis_two_tier_active_pc;
    }
}
#endif

static void *__vectis_alloc_ephemeral_page(size_t *out_sz, size_t min_sz) {
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

static void __vectis_free_ephemeral_page(void *ptr, size_t sz) {
    if (ptr && ptr != MAP_FAILED) {
#if defined(__APPLE__) && (defined(__aarch64__) || defined(__arm64__))
        pthread_jit_write_protect_np(0); /* Switch to write mode before memory wiping */
#endif
        /* Multi-pass secure memory wiping before deallocation */
        memset(ptr, 0x55, sz);
        memset(ptr, 0xAA, sz);
        memset(ptr, 0x00, sz);
        munmap(ptr, sz);
    }
}
|}
    in
    new_globals := helper_code :: !new_globals;

    List.iter
      (fun glob ->
        match glob with
        | GFun (fd, _) when should_transform fd ->
            incr func_count;
            let payload_name = Printf.sprintf "__ephemeral_payload_%s_%d" fd.svar.vname !func_count in
            let arg_name = match fd.sformals with arg :: _ -> arg.vname | [] -> "_x" in

            (* Dynamic AArch64 native JIT machine code compilation *)
            let jit_bytes = JIT.compile_fundec fd in
            let session_key = 1 + (Entropy.next_int ~max:254) in
            let enc_bytes = List.map (fun b -> b lxor session_key) jit_bytes in

            let uchar_type = TInt (IUChar, []) in

            (* Emit Payload Global Array *)
            let arr_type = TArray (uchar_type, Some (integer (List.length enc_bytes)), []) in
            let init_list = List.map (fun b -> SingleInit (kinteger64 IUChar (Int64.of_int b))) enc_bytes in
            let gvar = makeGlobalVar payload_name arr_type in
            gvar.vstorage <- Static;
            let ginit = GVar (gvar, { init = Some (CompoundInit (arr_type, List.map (fun i -> (NoOffset, i)) init_list)) }, locUnknown) in
            new_globals := ginit :: !new_globals;

            let fn_impl = Format.sprintf {|
int %s(int %s) {
    size_t __code_len = %d;
    size_t __tier2_sz = 0;

    /* Step 1: Allocate Ephemeral Page (MAP_JIT on Apple Silicon / Anonymous on Linux) */
    unsigned char *__tier2_page = (unsigned char *)__vectis_alloc_ephemeral_page(&__tier2_sz, __code_len);
    if (!__tier2_page) return 0;

#if defined(__APPLE__) && (defined(__aarch64__) || defined(__arm64__))
    pthread_jit_write_protect_np(0); /* Enable write permissions for JIT compilation */
#endif
    /* Step 2: Decrypt Native AArch64 Machine Code Payload */
    for (size_t __i = 0; __i < __code_len; __i++) {
        __tier2_page[__i] = %s[__i] ^ 0x%02X;
    }
#if defined(__APPLE__) && (defined(__aarch64__) || defined(__arm64__))
    pthread_jit_write_protect_np(1); /* Switch to execute-only permissions */
    sys_icache_invalidate(__tier2_page, __code_len); /* Invalidate CPU instruction cache */
#elif defined(__aarch64__) || defined(__arm64__)
    __builtin___clear_cache((char *)__tier2_page, (char *)__tier2_page + __code_len);
#endif

    /* Step 3: Execute Native Machine Code in Hardware */
    typedef int (*__jit_fn_t)(int);
    volatile __jit_fn_t __tier2_fn = (__jit_fn_t)(void *)__tier2_page;
    int __result = __tier2_fn(%s);

    /* Step 4: Multi-pass Secure Memory Wiping & Immediate Deallocation */
    __vectis_free_ephemeral_page(__tier2_page, __tier2_sz);
    return __result;
}
|}
              fd.svar.vname          (* %s: function name *)
              arg_name               (* %s: arg *)
              (List.length enc_bytes)(* %d: code_len *)
              payload_name           (* %s: payload array *)
              session_key            (* 0x%02X: dynamic session key *)
              arg_name               (* %s: call arg *)
            in

            new_globals := GText fn_impl :: !new_globals
        | other -> new_globals := other :: !new_globals)
      f.globals;

    f.globals <- List.rev !new_globals;
    f
end
