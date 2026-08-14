#include <sys/mman.h>
#include <unistd.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>

#ifdef __APPLE__
#include <libkern/OSCacheControl.h>
#include <pthread.h>
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
    "ocasorry.jit_handle",
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
    /* macOS Apple Silicon JIT allocation */
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
