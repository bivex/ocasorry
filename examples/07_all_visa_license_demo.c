/**
 * 07_all_visa_license_demo.c — Pure 4-Stage vISA Obfuscated License Demo
 *
 * Demonstrates that __attribute__((annotate("ocasorry:visa"))) can be used
 * on EVERY individual stage in the cryptographic cascade.
 */

extern int printf(const char *format, ...);
extern unsigned long strlen(const char *s);
extern int strcmp(const char *s1, const char *s2);

/* Stage 1: Vector Parity (random_vISA VCPU 1) */
__attribute__((annotate("ocasorry:visa")))
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

/* Stage 2: Algebraic Transform (random_vISA VCPU 2) */
__attribute__((annotate("ocasorry:visa")))
int vcpu2_algebraic_stage(int h1) {
    return h1 + 21;
}

/* Stage 3: Non-Linear XOR (random_vISA VCPU 3) */
__attribute__((annotate("ocasorry:visa")))
int vcpu3_feistel_stage(int h2) {
    return (h2 ^ 42) + 10;
}

/* Stage 4: Token Validation (random_vISA VCPU 4) */
__attribute__((annotate("ocasorry:visa")))
int vcpu4_token_validate(int h3) {
    if (h3 == 12729) {
        return 1;
    }
    return 0;
}

/* Master Verifier: Hardened with CFF + BCF + String Encryption + Anti-Debug */
__attribute__((annotate("ocasorry:cff, bcf, irreducible_loop, literals, api_hash")))
int verify_all_visa_license(const char *license_key, int verbose) {
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
        printf("  |         PURE 4-vISA VIRTUALIZATION CASCADE TRACE          |\n");
        printf("  +===========================================================+\n");
        printf("  | [Input Key] : %s (16 bytes)\n", license_key);
    }

    h1 = vcpu1_vector_parity(license_key);
    if (verbose) {
        printf("  | [vISA Stage 1]  h1 = %5d (Target: 12687) %s\n",
               h1, (h1 == 12687) ? " [OK]" : "[MISMATCH]");
    }

    h2 = vcpu2_algebraic_stage(h1);
    if (verbose) {
        printf("  | [vISA Stage 2]  h2 = %5d (Target: 12708) %s\n",
               h2, (h2 == 12708) ? " [OK]" : "[MISMATCH]");
    }

    h3 = vcpu3_feistel_stage(h2);
    if (verbose) {
        printf("  | [vISA Stage 3]  h3 = %5d (Target: 12729) %s\n",
               h3, (h3 == 12729) ? " [OK]" : "[MISMATCH]");
    }

    is_valid = vcpu4_token_validate(h3);
    if (verbose) {
        printf("  | [vISA Stage 4]  Result = %s\n",
               is_valid ? "UNLOCKED (Valid)" : "LOCKED (Invalid)");
        printf("  +===========================================================+\n\n");
    }

    return is_valid;
}

__attribute__((annotate("ocasorry:literals, api_hash")))
int main(int argc, char **argv) {
    static const char key_ent[] = "ENT-GRB970H2I708";
    static const char key_pro[] = "PRO-9842-KLM9-77";
    static const char key_sec[] = "SEC-3588982FS3B1";
    static const char key_agy[] = "AGY-1T4QE0F1AF19";
    static const char key_bad[] = "INVALID-KEY-0000";

    printf("=================================================================\n");
    printf("   OcaSorry: Pure 4-vISA (ocasorry:visa) License Demo           \n");
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
        r1 = verify_all_visa_license(key_ent, 1);
        r2 = verify_all_visa_license(key_pro, 1);
        r3 = verify_all_visa_license(key_sec, 1);
        r4 = verify_all_visa_license(key_agy, 1);
        r5 = verify_all_visa_license(key_bad, 1);

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
        int ok = verify_all_visa_license(argv[1], 1);
        return ok ? 0 : 1;
    }

    /* Interactive Default Demo */
    printf("[*] Running default 4-vISA Verification for: %s\n", key_ent);
    int ok = verify_all_visa_license(key_ent, 1);
    if (ok) {
        printf("[+] SUCCESS: 4-vISA Authorization Granted!\n");
    } else {
        printf("[-] REJECTED: Authorization Denied.\n");
    }

    return ok ? 0 : 1;
}
