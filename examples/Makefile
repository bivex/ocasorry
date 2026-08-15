# Makefile for Vectis C Examples
# Usage:
#   make CC=../_build/default/bin/vectis_cc.exe run

CC ?= clang
CFLAGS ?= -w -O2

SRCS = 01_license_keygen.c \
       02_aes_sbox_mini.c \
       03_state_machine_game.c \
       04_signal_auth_checker.c \
       05_multi_function_api.c \
       two_tier_jit_implicit_flow_demo.c

BINS = $(SRCS:.c=.bin)

all: $(BINS)

%.bin: %.c
	$(CC) $(CFLAGS) $< -o $@

run: all
	@echo "\n=== Running Example 01: License Key Verification ==="
	./01_license_keygen.bin PRO-9842-KLM9-77
	@echo "\n=== Running Example 02: Feistel Round & Non-Linear S-Box ==="
	./02_aes_sbox_mini.bin
	@echo "\n=== Running Example 03: State Machine & Turn Game ==="
	./03_state_machine_game.bin
	@echo "\n=== Running Example 04: Signal Auth Checker ==="
	./04_signal_auth_checker.bin 7391
	@echo "\n=== Running Example 05: Multi-Function Merging API ==="
	./05_multi_function_api.bin 3 4
	@echo "\n=== Running Two-Tier JIT Demo ==="
	./two_tier_jit_implicit_flow_demo.bin 100 200

clean:
	rm -f $(BINS)
