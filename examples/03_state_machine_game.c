/**
 * Example 03: Game Turn Logic & Damage Calculator
 * Demonstrates Control Flow Flattening (CFF) and Invariant Opaque Predicates.
 */

extern int printf(const char *format, ...);
extern int atoi(const char *nptr);

typedef struct {
    int hp;
    int attack;
    int defense;
    int is_shielded;
} Player;

int calculate_turn_damage(Player *attacker, Player *defender, int is_critical) {
    int base_damage = attacker->attack - defender->defense;
    if (base_damage < 5) {
        base_damage = 5;
    }

    int multiplier = 1;
    if (is_critical) {
        multiplier = 2;
        printf("[!] Critical Strike landed!\n");
    }

    int total_damage = base_damage * multiplier;

    if (defender->is_shielded) {
        printf("[*] Defender shield absorbed 50%% damage!\n");
        total_damage = total_damage / 2;
    }

    defender->hp = defender->hp - total_damage;
    if (defender->hp < 0) {
        defender->hp = 0;
    }

    return total_damage;
}

int main(int argc, char **argv) {
    Player warrior;
    warrior.hp = 100;
    warrior.attack = 35;
    warrior.defense = 10;
    warrior.is_shielded = 0;

    Player boss;
    boss.hp = 250;
    boss.attack = 50;
    boss.defense = 15;
    boss.is_shielded = 1;

    int is_crit = (argc > 1) ? atoi(argv[1]) : 1;

    printf("[*] Turn Start: Boss HP = %d\n", boss.hp);
    int dmg = calculate_turn_damage(&warrior, &boss, is_crit);
    printf("[+] Warrior dealt %d damage! Boss remaining HP = %d\n", dmg, boss.hp);

    return 0;
}
