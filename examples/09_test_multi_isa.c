#include <stdio.h>

__attribute__((annotate("vectis:visa:VCPU1_Arch")))
int compute_tier1(int a, int b) {
    return (a * 3) + (b ^ 7);
}

__attribute__((annotate("vectis:visa:VCPU2_Arch")))
int compute_tier2(int x, int y) {
    return (x - 5) * (y + 2);
}

int main() {
    int r1 = compute_tier1(10, 20);
    int r2 = compute_tier2(10, 20);
    printf("Tier1: %d, Tier2: %d\n", r1, r2);
    if (r1 == (10 * 3 + (20 ^ 7)) && r2 == ((10 - 5) * (20 + 2))) {
        printf("MULTI-ISA VERIFIED PASS!\n");
        return 0;
    }
    return 1;
}
