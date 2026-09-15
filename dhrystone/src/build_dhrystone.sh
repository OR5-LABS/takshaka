#!/usr/bin/env bash
# build_dhrystone.sh — compile Dhrystone 2.1 for Takshaka simulation.
# Usage: ./build_dhrystone.sh [NUMBER_OF_RUNS]
set -euo pipefail
cd "$(dirname "$0")"

TC="${RISCV_TC:-/home/yash/toolchains/xpack-riscv-none-elf-gcc-13.2.0-2/bin}"
GCC="${GCC:-$TC/riscv-none-elf-gcc}"
OBJCOPY="${OBJCOPY:-$TC/riscv-none-elf-objcopy}"

# Toolchain auto-detect
if ! command -v "$GCC" &>/dev/null; then
  if command -v riscv-none-elf-gcc &>/dev/null; then
    GCC="riscv-none-elf-gcc"; OBJCOPY="riscv-none-elf-objcopy"
  elif command -v riscv32-unknown-elf-gcc &>/dev/null; then
    GCC="riscv32-unknown-elf-gcc"; OBJCOPY="riscv32-unknown-elf-objcopy"
  else
    echo "ERROR: RISC-V GCC toolchain not found." >&2; exit 1
  fi
fi

RUNS="${1:-500000}"
LDSCRIPT="${LDSCRIPT:-link.ld}"

FLAGS="-O2 -march=rv32imc -mabi=ilp32 -nostartfiles -fno-pic -Wl,--no-relax"
INCLUDES="-I."

echo "Compiling Dhrystone for Takshaka (${RUNS} runs)..."

"$GCC" $FLAGS $INCLUDES -T "$LDSCRIPT" \
    -DNUMBER_OF_RUNS="${RUNS}" \
    -DCLK_FREQ_HZ=100000000 \
    -DCOMPILER_VERSION="\"$("$GCC" --version | head -1)\"" \
    -DCOMPILER_FLAGS="\"$FLAGS\"" \
    start.S \
    dhry_1.c \
    dhry_2.c \
    dhry_port.c \
    -o dhrystone.elf

echo "Generating hex..."
"$OBJCOPY" -O binary dhrystone.elf dhrystone.bin
python3 ../../sw/bin2hex.py dhrystone.bin dhrystone.hex
echo "Done. dhrystone.hex is ready."
