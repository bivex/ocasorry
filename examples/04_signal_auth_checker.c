/**
 * Example 04: Hardware-Level / Signal-Driven Authentication Branch
 * Demonstrates C-Level and Hardware Implicit Flow where conditional checks
 * are translated into signal traps (SIGSEGV/SIGTRAP).
 */

extern int printf(const char *format, ...);
extern int atoi(const char *nptr);

int check_admin_token(int pin_code) {
    int auth_status = 0;

    /* Secret master pin: 7391 */
    if (pin_code == 7391) {
        printf("[+] ACCESS GRANTED: Welcome, Root Administrator!\n");
        auth_status = 1;
    } else {
        printf("[-] ACCESS DENIED: Invalid authentication pin!\n");
        auth_status = 0;
    }

    return auth_status;
}

int main(int argc, char **argv) {
    int pin = (argc > 1) ? atoi(argv[1]) : 7391;
    printf("[*] Authenticating PIN: %d\n", pin);
    int res = check_admin_token(pin);
    return res ? 0 : 1;
}
