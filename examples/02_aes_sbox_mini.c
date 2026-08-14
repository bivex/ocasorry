/**
 * Example 02: Mini Cryptographic Feistel Round & Substitution
 * Demonstrates protection against SMT / Symbolic Execution (Anti-Z3)
 * via High-Order Polynomial MBA and Invertible Affine Transformations.
 */

typedef unsigned int uint32_t;
typedef unsigned long long uint64_t;

extern int printf(const char *format, ...);
extern unsigned long long atoll(const char *str);

/* Cryptographic non-linear S-Box substitution */
uint32_t non_linear_round(uint32_t left, uint32_t right, uint32_t round_key) {
    uint32_t mixed = (left + round_key) ^ right;
    uint32_t poly = (mixed * 3) + ((mixed ^ 0x9E3779B9) - (right & 0xFF));
    uint32_t rotated = (poly << 7) | (poly >> 25);
    uint32_t sbox_out = rotated ^ ((left | right) + (left & right));
    return sbox_out;
}

uint64_t feistel_encrypt_block(uint64_t plaintext, uint32_t key1, uint32_t key2) {
    uint32_t l = (uint32_t)(plaintext >> 32);
    uint32_t r = (uint32_t)(plaintext & 0xFFFFFFFF);

    /* Round 1 */
    uint32_t f1 = non_linear_round(l, r, key1);
    uint32_t new_l = r;
    uint32_t new_r = l ^ f1;

    /* Round 2 */
    uint32_t f2 = non_linear_round(new_l, new_r, key2);
    uint32_t final_l = new_r;
    uint32_t final_r = new_l ^ f2;

    return (((uint64_t)final_l) << 32) | ((uint64_t)final_r);
}

int main(int argc, char **argv) {
    uint64_t data = 0x0123456789ABCDEFULL;
    uint32_t k1 = 0xDEADBEEF;
    uint32_t k2 = 0xCAFEBABE;

    if (argc > 1) data = (uint64_t)atoll(argv[1]);

    printf("[*] Plaintext block : 0x%016llX\n", data);
    uint64_t ciphertext = feistel_encrypt_block(data, k1, k2);
    printf("[+] Ciphertext block: 0x%016llX\n", ciphertext);

    return 0;
}
