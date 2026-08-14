/**
 * Example 05: Multi-Function Math Library
 * Demonstrates Function Merging (Tigress Merge) and Function Outlining (Tigress Outline).
 */

extern int printf(const char *format, ...);
extern int atoi(const char *nptr);

int compute_hypotenuse_squared(int a, int b) {
    int a2 = a * a;
    int b2 = b * b;
    int sum = a2 + b2;
    return sum;
}

int compute_manhattan_distance(int x1, int y1, int x2, int y2) {
    int dx = (x1 > x2) ? (x1 - x2) : (x2 - x1);
    int dy = (y1 > y2) ? (y1 - y2) : (y2 - y1);
    int total = dx + dy;
    return total;
}

int main(int argc, char **argv) {
    int a = (argc > 1) ? atoi(argv[1]) : 3;
    int b = (argc > 2) ? atoi(argv[2]) : 4;

    int hyp_sq = compute_hypotenuse_squared(a, b);
    int dist = compute_manhattan_distance(0, 0, a, b);

    printf("[+] Hypotenuse Squared (%d, %d) = %d\n", a, b, hyp_sq);
    printf("[+] Manhattan Distance from (0,0) = %d\n", dist);

    return 0;
}
