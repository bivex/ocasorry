#define _DARWIN_C_SOURCE
#include <sys/mman.h>
#include <unistd.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <signal.h>

#ifdef __APPLE__
#include <libkern/OSCacheControl.h>
#include <pthread.h>
#include <sys/ucontext.h>
#endif

#define CAML_NAME_SPACE
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>

typedef struct {
    void *ptr;
    size_t size;
} jit_handle_t;

#define Jit_handle_val(v) (*((jit_handle_t **) Data_custom_val(v)))

static void finalize_jit_handle(value v) {
    jit_handle_t *h = Jit_handle_val(v);
    if (h != NULL) {
        if (h->ptr != NULL && h->ptr != MAP_FAILED) {
            munmap(h->ptr, h->size);
        }
        free(h);
    }
}

static struct custom_operations jit_handle_ops = {
    "vectis.jit_handle",
    finalize_jit_handle,
    custom_compare_default,
    custom_hash_default,
    custom_serialize_default,
    custom_deserialize_default,
    custom_compare_ext_default,
    custom_fixed_length_default
};

CAMLprim value caml_jit_allocate(value v_bytes) {
    CAMLparam1(v_bytes);
    CAMLlocal1(v_res);

    mlsize_t len = caml_string_length(v_bytes);
    size_t page_size = (size_t)sysconf(_SC_PAGESIZE);
    size_t alloc_size = (len + page_size - 1) & ~(page_size - 1);

#ifdef __APPLE__
    void *mem = mmap(NULL, alloc_size, PROT_READ | PROT_WRITE | PROT_EXEC,
                     MAP_ANON | MAP_PRIVATE | MAP_JIT, -1, 0);
    if (mem == MAP_FAILED) {
        caml_failwith("mmap MAP_JIT failed");
    }

    pthread_jit_write_protect_np(0);
    memcpy(mem, String_val(v_bytes), len);
    pthread_jit_write_protect_np(1);
    sys_icache_invalidate(mem, len);
#else
    void *mem = mmap(NULL, alloc_size, PROT_READ | PROT_WRITE,
                     MAP_ANON | MAP_PRIVATE, -1, 0);
    if (mem == MAP_FAILED) {
        caml_failwith("mmap RW failed");
    }
    memcpy(mem, String_val(v_bytes), len);
    if (mprotect(mem, alloc_size, PROT_READ | PROT_EXEC) != 0) {
        munmap(mem, alloc_size);
        caml_failwith("mprotect RX failed");
    }
    __builtin___clear_cache((char*)mem, (char*)mem + len);
#endif

    jit_handle_t *handle = (jit_handle_t *)malloc(sizeof(jit_handle_t));
    handle->ptr = mem;
    handle->size = alloc_size;

    v_res = caml_alloc_custom(&jit_handle_ops, sizeof(jit_handle_t *), 0, 1);
    Jit_handle_val(v_res) = handle;

    CAMLreturn(v_res);
}

typedef int64_t (*jit_fn1_t)(int64_t);
typedef int64_t (*jit_fn2_t)(int64_t, int64_t);

CAMLprim value caml_jit_run_fn1(value v_handle, value v_arg) {
    CAMLparam2(v_handle, v_arg);
    jit_handle_t *h = Jit_handle_val(v_handle);
    if (h == NULL || h->ptr == NULL) {
        caml_failwith("Invalid JIT handle");
    }

    int64_t arg = Int64_val(v_arg);
    jit_fn1_t fn = (jit_fn1_t)h->ptr;
    int64_t res = fn(arg);

    CAMLreturn(caml_copy_int64(res));
}

CAMLprim value caml_jit_run_fn2(value v_handle, value v_arg1, value v_arg2) {
    CAMLparam3(v_handle, v_arg1, v_arg2);
    jit_handle_t *h = Jit_handle_val(v_handle);
    if (h == NULL || h->ptr == NULL) {
        caml_failwith("Invalid JIT handle");
    }

    int64_t arg1 = Int64_val(v_arg1);
    int64_t arg2 = Int64_val(v_arg2);
    jit_fn2_t fn = (jit_fn2_t)h->ptr;
    int64_t res = fn(arg1, arg2);

    CAMLreturn(caml_copy_int64(res));
}

CAMLprim value caml_jit_free(value v_handle) {
    CAMLparam1(v_handle);
    jit_handle_t *h = Jit_handle_val(v_handle);
    if (h != NULL) {
        if (h->ptr != NULL && h->ptr != MAP_FAILED) {
            munmap(h->ptr, h->size);
            h->ptr = NULL;
        }
    }
    CAMLreturn(Val_unit);
}

/* ========================================================================= */
/* Two-Tier JIT Engine + Hardware Implicit Flow Signal Router               */
/* ========================================================================= */

static void *g_tier2_target_pc = NULL;

#if defined(__APPLE__) && defined(__aarch64__)
static void two_tier_sig_handler(int sig, siginfo_t *info, void *context) {
    (void)sig;
    (void)info;
    ucontext_t *uc = (ucontext_t *)context;
    if (g_tier2_target_pc != NULL) {
        /* Implicit Flow: Hardware redirect PC to decrypted Tier 2 Entry point */
        uc->uc_mcontext->__ss.__pc = (uint64_t)g_tier2_target_pc;
    }
}
#endif

CAMLprim value caml_two_tier_jit_run(value v_tier1_bytes, value v_tier2_enc_bytes, value v_key, value v_arg1, value v_arg2) {
    CAMLparam5(v_tier1_bytes, v_tier2_enc_bytes, v_key, v_arg1, v_arg2);

    mlsize_t tier1_len = caml_string_length(v_tier1_bytes);
    mlsize_t tier2_len = caml_string_length(v_tier2_enc_bytes);
    int key = Int_val(v_key);
    int64_t arg1 = Int64_val(v_arg1);
    int64_t arg2 = Int64_val(v_arg2);

    size_t page_size = (size_t)sysconf(_SC_PAGESIZE);
    size_t alloc1_size = (tier1_len + page_size - 1) & ~(page_size - 1);
    size_t alloc2_size = (tier2_len + page_size - 1) & ~(page_size - 1);

    /* 1. Allocate Tier 2 (Inner Payload JIT Page) & Decrypt on the fly */
    void *tier2_mem = mmap(NULL, alloc2_size, PROT_READ | PROT_WRITE | PROT_EXEC,
                           MAP_ANON | MAP_PRIVATE | MAP_JIT, -1, 0);
    if (tier2_mem == MAP_FAILED) {
        caml_failwith("Tier 2 mmap failed");
    }

    const unsigned char *enc_data = (const unsigned char *)String_val(v_tier2_enc_bytes);
    unsigned char *dec_buf = (unsigned char *)malloc(tier2_len);
    for (mlsize_t i = 0; i < tier2_len; i++) {
        dec_buf[i] = enc_data[i] ^ (unsigned char)key;
    }

    pthread_jit_write_protect_np(0);
    memcpy(tier2_mem, dec_buf, tier2_len);
    pthread_jit_write_protect_np(1);
    sys_icache_invalidate(tier2_mem, tier2_len);
    free(dec_buf);

    g_tier2_target_pc = tier2_mem;

    /* 2. Allocate Tier 1 (Outer Dispatcher / Fault Trigger JIT Page) */
    void *tier1_mem = mmap(NULL, alloc1_size, PROT_READ | PROT_WRITE | PROT_EXEC,
                           MAP_ANON | MAP_PRIVATE | MAP_JIT, -1, 0);
    if (tier1_mem == MAP_FAILED) {
        munmap(tier2_mem, alloc2_size);
        caml_failwith("Tier 1 mmap failed");
    }

    pthread_jit_write_protect_np(0);
    memcpy(tier1_mem, String_val(v_tier1_bytes), tier1_len);
    pthread_jit_write_protect_np(1);
    sys_icache_invalidate(tier1_mem, tier1_len);

    /* 3. Install Signal Handlers for Hardware Implicit Flow */
    struct sigaction sa, old_sigtrap, old_sigbus, old_sigsegv, old_sigill;
    memset(&sa, 0, sizeof(sa));
#if defined(__APPLE__) && defined(__aarch64__)
    sa.sa_sigaction = two_tier_sig_handler;
    sa.sa_flags = SA_SIGINFO;
#endif
    sigaction(SIGTRAP, &sa, &old_sigtrap);
    sigaction(SIGBUS, &sa, &old_sigbus);
    sigaction(SIGSEGV, &sa, &old_sigsegv);
    sigaction(SIGILL, &sa, &old_sigill);

    /* 4. Execute Tier 1 (Which triggers implicit trap to Tier 2 in hardware) */
    jit_fn2_t tier1_fn = (jit_fn2_t)tier1_mem;
    int64_t result = tier1_fn(arg1, arg2);

    /* 5. Restore Signal Handlers & Cleanup Memory */
    sigaction(SIGTRAP, &old_sigtrap, NULL);
    sigaction(SIGBUS, &old_sigbus, NULL);
    sigaction(SIGSEGV, &old_sigsegv, NULL);
    sigaction(SIGILL, &old_sigill, NULL);

    g_tier2_target_pc = NULL;
    munmap(tier1_mem, alloc1_size);
    munmap(tier2_mem, alloc2_size);

    CAMLreturn(caml_copy_int64(result));
}
