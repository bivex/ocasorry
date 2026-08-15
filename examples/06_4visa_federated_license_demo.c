/**
 * 06_4visa_federated_license_demo.c — Interactive 4-vISA Federated License Demo
 *
 * Demonstrates the 4-Tier Federated Virtualization Cascade:
 *  - Tier 1 (VCPU 1: vISA):        Vectorized Non-Linear Parity & Galois Field Accumulator
 *  - Tier 2 (VCPU 2: Nested VM):   2-Tier Outer/Inner Hierarchical Stack Machine
 *  - Tier 3 (VCPU 3: Rolling Key): Dynamic LCG Rolling VKey Mutator
 *  - Tier 4 (VCPU 4: Ephemeral):   Self-Wiping In-Memory JIT Token Verifier
 */

extern int printf(const char *format, ...);
extern unsigned long strlen(const char *s);
extern int rand(void);
extern void srand(unsigned int seed);
extern int strcmp(const char *s1, const char *s2);
extern int atoi(const char *nptr);

/* ========================================================================= */
/* TIER 1: Vector Processor vISA (random_vISA VCPU 1)                        */
/* ========================================================================= */
__attribute__((annotate("vectis:visa")))
int vcpu1_vector_parity(const char *license_key) {
    int acc = 0x1337;
    int parity = 0x5A;
    int i = 0;
    for (i = 0; i < 16; i++) {
        int ch = (int)((unsigned char)license_key[i]);
        acc = (acc + (ch * (i + 1))) ^ parity;
        parity = (parity + ch) & 0xFF;
    }
    return acc;
}

/* ========================================================================= */
/* TIER 2: Nested Multi-Layer VM (Nested Stack VCPU 2)                       */
/* ========================================================================= */
__attribute__((annotate("vectis:nested_vm")))
int vcpu2_nested_matrix(int h1) {
    return h1 + 21;
}

/* ========================================================================= */
/* TIER 3: Stateful Rolling Key VM (Rolling VKey VCPU 3)                     */
/* ========================================================================= */
__attribute__((annotate("vectis:rolling_vkey")))
int vcpu3_rolling_vkey(int h2) {
    return ((h2 + 10) ^ 42) * 2;
}

/* ========================================================================= */
/* TIER 4: Ephemeral In-Memory JIT VM (Self-Wiping VCPU 4)                  */
/* ========================================================================= */
__attribute__((annotate("vectis:ephemeral")))
int vcpu4_ephemeral_jit(int h3) {
    return (h3 == 25352) ? 1 : 0;
}

/* ========================================================================= */
/* Master Federated License Verifier                                         */
/* ========================================================================= */
__attribute__((annotate("vectis:cff, irreducible_loop, bcf, literals")))
int verify_license_cascade(const char *license_key, int verbose) {
    int h1 = 0;
    int h2 = 0;
    int h3 = 0;
    int is_valid = 0;

    if (license_key == (void*)0 || strlen(license_key) != 16) {
        if (verbose) printf("  [-] Invalid key format: Must be exactly 16 characters.\n");
        return 0;
    }

    if (verbose) {
        printf("\n  +===========================================================+\n");
        printf("  |       4-vISA FEDERATED VIRTUALIZATION CASCADE TRACE       |\n");
        printf("  +===========================================================+\n");
        printf("  | [Input Key] : %s (16 bytes)\n", license_key);
    }

    /* Step 1: vISA Tier 1 */
    h1 = vcpu1_vector_parity(license_key);
    if (verbose) {
        printf("  | [Tier 1 vISA]    h1 = %5d (Target: 12687) %s\n",
               h1, (h1 == 12687) ? " [OK]" : "[MISMATCH]");
    }

    /* Step 2: Nested VM Tier 2 */
    h2 = vcpu2_nested_matrix(h1);
    if (verbose) {
        printf("  | [Tier 2 Nested]  h2 = %5d (Target: 12708) %s\n",
               h2, (h2 == 12708) ? " [OK]" : "[MISMATCH]");
    }

    /* Step 3: Rolling Key Tier 3 */
    h3 = vcpu3_rolling_vkey(h2);
    if (verbose) {
        printf("  | [Tier 3 Rolling] h3 = %5d (Target: 25352) %s\n",
               h3, (h3 == 25352) ? " [OK]" : "[MISMATCH]");
    }

    /* Step 4: Ephemeral JIT Tier 4 */
    is_valid = vcpu4_ephemeral_jit(h3);
    if (verbose) {
        printf("  | [Tier 4 JIT]     Result = %s\n",
               is_valid ? "UNLOCKED (Valid)" : "LOCKED (Invalid)");
        printf("  +===========================================================+\n\n");
    }

    return is_valid;
}

/* ========================================================================= */
/* Interactive CLI Interface                                                 */
/* ========================================================================= */
__attribute__((annotate("vectis:literals, api_hash")))
int main(int argc, char **argv) {
    /* Hardcoded valid keys with different prefixes for instant CLI demonstration */
    static const char key_ent[] = "ENT-GRB970H2I708";
    static const char key_pro[] = "PRO-9842-KLM9-77";
    static const char key_sec[] = "SEC-3588982FS3B1";
    static const char key_agy[] = "AGY-1T4QE0F1AF19";
    static const char key_bad[] = "INVALID-KEY-0000";

    printf("=================================================================\n");
    printf("     Vectis: 4-vISA Federated Virtualization License Demo      \n");
    printf("=================================================================\n");

    if (argc > 1 && (strcmp(argv[1], "-h") == 0 || strcmp(argv[1], "--help") == 0)) {
        printf("Usage:\n");
        printf("  %s                      Run interactive 4-vISA demo\n", argv[0]);
        printf("  %s <key>                Verify specific 16-char license key\n", argv[0]);
        printf("  %s --list               List available pre-generated keys\n", argv[0]);
        printf("  %s --test               Run full 4-vISA verification suite\n", argv[0]);
        return 0;
    }

    if (argc > 1 && strcmp(argv[1], "--list") == 0) {
        printf("[*] Available Verified 4-vISA License Keys:\n");
        printf("  [01] %s (Enterprise)\n", key_ent);
        printf("  [02] %s (Professional)\n", key_pro);
        printf("  [03] %s (Security)\n", key_sec);
        printf("  [04] %s (Antigravity)\n", key_agy);
        return 0;
    }

    if (argc > 1 && strcmp(argv[1], "--test") == 0) {
        int r1 = 0;
        int r2 = 0;
        int r3 = 0;
        int r4 = 0;
        int r5 = 0;
        printf("[*] Running 4-vISA verification test suite...\n");
        r1 = verify_license_cascade(key_ent, 1);
        r2 = verify_license_cascade(key_pro, 1);
        r3 = verify_license_cascade(key_sec, 1);
        r4 = verify_license_cascade(key_agy, 1);
        r5 = verify_license_cascade(key_bad, 1);

        printf("Results Summary:\n");
        printf("  - Enterprise Key (%s) : %s\n", key_ent, r1 ? "PASS (Unlocked)" : "FAIL");
        printf("  - Pro Golden Key (%s) : %s\n", key_pro, r2 ? "PASS (Unlocked)" : "FAIL");
        printf("  - Security Key   (%s) : %s\n", key_sec, r3 ? "PASS (Unlocked)" : "FAIL");
        printf("  - AGY Key        (%s) : %s\n", key_agy, r4 ? "PASS (Unlocked)" : "FAIL");
        printf("  - Corrupted Key  (%s) : %s\n", key_bad, (!r5) ? "PASS (Blocked)" : "FAIL");
        return (r1 && r2 && r3 && r4 && !r5) ? 0 : 1;
    }

    /* Single key argument */
    if (argc > 1 && argv[1][0] != '-') {
        int ok = verify_license_cascade(argv[1], 1);
        return ok ? 0 : 1;
    }

    /* Interactive Default Demo */
    printf("[*] Running default 4-vISA Federated Verification for: %s\n", key_ent);
    int ok = verify_license_cascade(key_ent, 1);
    if (ok) {
        printf("[+] SUCCESS: 4-vISA Federated Authorization Granted!\n");
    } else {
        printf("[-] REJECTED: Authorization Denied.\n");
    }

    return ok ? 0 : 1;
}
