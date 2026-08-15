/**
 * Example 01 Companion: Standalone C License Keygen & Verifier
 * Generates and validates keys for the 4-VCPU Federated Virtualization Target.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define TARGET_H1 12687
#define TARGET_H2 12708
#define TARGET_H3 25352

static const char ALPHABET[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
static const int ALPHABET_LEN = 36;

int vcpu1_vector_parity(const char *license_key) {
    int acc = 0x1337;
    int parity = 0x5A;
    for (int i = 0; i < 16; i++) {
        int ch = (int)((unsigned char)license_key[i]);
        acc = (acc + (ch * (i + 1))) ^ parity;
        parity = (parity + ch) & 0xFF;
    }
    return acc;
}

int vcpu2_nested_matrix(int h1) {
    return h1 + 21;
}

int vcpu3_rolling_vkey(int h2) {
    return ((h2 + 10) ^ 42) * 2;
}

int vcpu4_ephemeral_jit(int h3) {
    return (h3 == TARGET_H3) ? 1 : 0;
}

int verify_key(const char *key) {
    if (!key || strlen(key) != 16) return 0;
    int h1 = vcpu1_vector_parity(key);
    int h2 = vcpu2_nested_matrix(h1);
    int h3 = vcpu3_rolling_vkey(h2);
    return vcpu4_ephemeral_jit(h3);
}

void generate_valid_key(const char *prefix, char *out_key) {
    char base[17];
    memset(base, 0, sizeof(base));
    int prefix_len = (int)strlen(prefix);
    if (prefix_len > 4) prefix_len = 4;
    strncpy(base, prefix, prefix_len);

    while (1) {
        /* Generate random characters up to index 13 */
        for (int i = prefix_len; i < 14; i++) {
            base[i] = ALPHABET[rand() % ALPHABET_LEN];
        }

        /* Fast suffix solve for index 14 and 15 (36 * 36 combinations) */
        int acc = 0x1337;
        int parity = 0x5A;
        for (int i = 0; i < 14; i++) {
            int ch = (int)((unsigned char)base[i]);
            acc = (acc + (ch * (i + 1))) ^ parity;
            parity = (parity + ch) & 0xFF;
        }

        for (int i1 = 0; i1 < ALPHABET_LEN; i1++) {
            char c1 = ALPHABET[i1];
            int ch1 = (int)((unsigned char)c1);
            int acc1 = (acc + (ch1 * 15)) ^ parity;
            int par1 = (parity + ch1) & 0xFF;

            for (int i2 = 0; i2 < ALPHABET_LEN; i2++) {
                char c2 = ALPHABET[i2];
                int ch2 = (int)((unsigned char)c2);
                int acc2 = (acc1 + (ch2 * 16)) ^ par1;

                if (acc2 == TARGET_H1) {
                    base[14] = c1;
                    base[15] = c2;
                    base[16] = '\0';
                    strcpy(out_key, base);
                    return;
                }
            }
        }
    }
}

int main(int argc, char **argv) {
    srand((unsigned int)time(NULL));

    if (argc > 1 && strcmp(argv[1], "--check") == 0) {
        if (argc < 3) {
            printf("Usage: %s --check <license_key>\n", argv[0]);
            return 1;
        }
        const char *key = argv[2];
        int h1 = vcpu1_vector_parity(key);
        int h2 = vcpu2_nested_matrix(h1);
        int h3 = vcpu3_rolling_vkey(h2);
        int valid = vcpu4_ephemeral_jit(h3);

        printf("=================================================================\n");
        printf("       C Keygen Verifier: %s\n", key);
        printf("=================================================================\n");
        printf("  Length        : %lu / 16 chars\n", (unsigned long)strlen(key));
        printf("  VCPU 1 (h1)   : %d (Target: %d)\n", h1, TARGET_H1);
        printf("  VCPU 2 (h2)   : %d (Target: %d)\n", h2, TARGET_H2);
        printf("  VCPU 3 (h3)   : %d (Target: %d)\n", h3, TARGET_H3);
        printf("  VCPU 4 Result : %s\n", valid ? "UNLOCKED (Valid Key)" : "REJECTED (Invalid Key)");
        printf("=================================================================\n");
        return valid ? 0 : 1;
    }

    int count = (argc > 1) ? atoi(argv[1]) : 5;
    const char *prefix = (argc > 2) ? argv[2] : "PRO-";
    if (count <= 0) count = 5;

    printf("=================================================================\n");
    printf("   Vectis Native C Keygen (%d keys generated with prefix '%s')\n", count, prefix);
    printf("=================================================================\n");

    char key_buf[17];
    for (int i = 1; i <= count; i++) {
        generate_valid_key(prefix, key_buf);
        int valid = verify_key(key_buf);
        printf("  [%02d] %s  -> [4-VCPU Verified: %s]\n", i, key_buf, valid ? "VALID" : "INVALID");
    }
    printf("=================================================================\n");
    return 0;
}
