/**
 * Example 01: Software License Key Verification
 * Demonstrates protection against string extraction (EncodeLiterals),
 * memory tampering (VariableSplitting), and mathematical inversion (Linear MBA).
 */

extern int printf(const char *format, ...);
extern unsigned long strlen(const char *s);

/* Computes non-linear checksum of a license key string */
int verify_license_key(const char *license_key) {
    if (license_key == (void*)0 || strlen(license_key) != 16) {
        printf("[-] Invalid key format: Must be exactly 16 characters.\n");
        return 0;
    }

    int accumulator = 0x1337;
    int parity = 0x5A;

    for (int i = 0; i < 16; i++) {
        int ch = (int)((unsigned char)license_key[i]);
        accumulator = (accumulator + (ch * (i + 1))) ^ parity;
        parity = (parity + ch) & 0xFF;
    }

    int expected_hash = 0x318F; /* Secret key target hash for PRO-9842-KLM9-77 */

    if ((accumulator ^ 0xDEAD) == (expected_hash ^ 0xDEAD)) {
        printf("[+] SUCCESS: License key is VALID! Unlocking premium features...\n");
        return 1;
    } else {
        printf("[-] FAILED: Invalid license key! Access denied.\n");
        return 0;
    }
}

int main(int argc, char **argv) {
    const char *key = (argc > 1) ? argv[1] : "PRO-9842-KLM9-77";
    printf("[*] Verifying Key: %s\n", key);
    int res = verify_license_key(key);
    return res ? 0 : 1;
}
