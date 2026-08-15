/**
 * Example 02: 8-VCPU Federated Mini AES / Feistel Cryptographic Block Cipher
 *
 * Demonstrates 8 distinct Virtual Machines cascading across 2 rounds of Feistel
 * without nested_vm:
 *  - VCPU 1: Vector ISA (random_vISA) - Subkey Expansion
 *  - VCPU 2: Rolling Key VM (rolling_vkey) - Round 1 S-Box Non-Linear Substitution
 *  - VCPU 3: Vector ISA (random_vISA) - Round 1 Diffusion & Mix-Column
 *  - VCPU 4: Rolling Key VM (rolling_vkey) - Round 1 Feistel Cross-Over
 *  - VCPU 5: Rolling Key VM (rolling_vkey) - Round 2 S-Box Non-Linear Substitution
 *  - VCPU 6: Vector ISA (random_vISA) - Round 2 Diffusion & Mix-Column
 *  - VCPU 7: Rolling Key VM (rolling_vkey) - Round 2 Feistel Cross-Over
 *  - VCPU 8: Ephemeral JIT Wiper (ephemeral_jit) - Two-Tier Hardware JIT Finalizer
 */

typedef unsigned int uint32_t;
typedef unsigned long long uint64_t;

extern int printf(const char *format, ...);
extern long long atoll(const char *str);

/* VCPU 1 (Vector ISA): Subkey Expansion & Key Schedule */
__attribute__((annotate("ocasorry:visa")))
int vcpu1_expand_key(int key) {
    int mixed = (key ^ 0x9E3779B9) + 0x1337;
    return mixed;
}

/* VCPU 2 (Rolling Key VM): Round 1 Non-Linear S-Box */
__attribute__((annotate("ocasorry:rolling_vkey")))
int vcpu2_sub_bytes_r1(int left) {
    int sbox = ((left + 10) ^ 42) * 2;
    return sbox;
}

/* VCPU 3 (Vector ISA): Round 1 Diffusion & ShiftMix */
__attribute__((annotate("ocasorry:visa")))
int vcpu3_shift_mix_r1(int sbox_out, int right) {
    int mixed = (sbox_out ^ right) + 17;
    return mixed;
}

/* VCPU 4 (Rolling Key VM): Round 1 Feistel Cross-Over */
__attribute__((annotate("ocasorry:rolling_vkey")))
int vcpu4_feistel_xor_r1(int left) {
    int res = ((left + 15) ^ 99) * 2;
    return res;
}

/* VCPU 5 (Rolling Key VM): Round 2 Non-Linear S-Box */
__attribute__((annotate("ocasorry:rolling_vkey")))
int vcpu5_sub_bytes_r2(int new_left) {
    int sbox2 = ((new_left + 25) ^ 77) * 2;
    return sbox2;
}

/* VCPU 6 (Vector ISA): Round 2 Diffusion & ShiftMix */
__attribute__((annotate("ocasorry:visa")))
int vcpu6_shift_mix_r2(int sbox_out2, int new_right) {
    int mixed2 = (sbox_out2 ^ new_right) + 31;
    return mixed2;
}

/* VCPU 7 (Rolling Key VM): Round 2 Feistel Cross-Over */
__attribute__((annotate("ocasorry:rolling_vkey")))
int vcpu7_feistel_xor_r2(int new_left) {
    int res2 = ((new_left + 35) ^ 123) * 2;
    return res2;
}

/* VCPU 8 (Ephemeral JIT): Hardware Fault Two-Tier JIT Finalizer */
__attribute__((annotate("ocasorry:ephemeral")))
int vcpu8_ephemeral_finalize(int final_val) {
    return (final_val != 0) ? 1 : 0;
}

/* Master 8-VCPU Federated Orchestrator */
__attribute__((annotate("ocasorry:cff, irreducible_loop, bcf, literals")))
uint64_t feistel_8vcpu_encrypt(uint32_t left, uint32_t right, uint32_t key1, uint32_t key2) {
    /* VCPU 1: Subkey expansion */
    int k1_exp = vcpu1_expand_key((int)key1);
    int k2_exp = vcpu1_expand_key((int)key2);

    /* --- ROUND 1 --- */
    /* VCPU 2: S-Box */
    int sbox1 = vcpu2_sub_bytes_r1((int)left + k1_exp);
    /* VCPU 3: Diffusion */
    int f1 = vcpu3_shift_mix_r1(sbox1, (int)right);
    /* VCPU 4: Feistel Cross */
    int new_left = (int)right;
    int new_right = vcpu4_feistel_xor_r1((int)left ^ f1);

    /* --- ROUND 2 --- */
    /* VCPU 5: S-Box */
    int sbox2 = vcpu5_sub_bytes_r2(new_left + k2_exp);
    /* VCPU 6: Diffusion */
    int f2 = vcpu6_shift_mix_r2(sbox2, new_right);
    /* VCPU 7: Feistel Cross */
    int final_left = new_right;
    int final_right = vcpu7_feistel_xor_r2(new_left ^ f2);

    /* VCPU 8: Ephemeral Two-Tier JIT Validation */
    int status = vcpu8_ephemeral_finalize(final_right);
    if (!status) {
        printf("[-] VCPU 8 Security Check Failed\n");
        return 0ULL;
    }

    uint64_t out = (((uint64_t)(unsigned int)final_left) << 32) | ((uint64_t)(unsigned int)final_right);
    return out;
}

int main(int argc, char **argv) {
    uint32_t left = 0x12345678;
    uint32_t right = 0x9ABCDEF0;
    uint32_t k1 = 0xDEADBEEF;
    uint32_t k2 = 0xCAFEBABE;

    if (argc > 1) left = (uint32_t)atoll(argv[1]);
    if (argc > 2) right = (uint32_t)atoll(argv[2]);

    printf("[*] 8-VCPU Plaintext Block : [L: 0x%08X, R: 0x%08X]\n", left, right);
    uint64_t cipher = feistel_8vcpu_encrypt(left, right, k1, k2);
    printf("[+] 8-VCPU Ciphertext Block: 0x%016llX\n", cipher);

    return 0;
}
