#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

TC="${RISCV_TC:-/home/yash/toolchains/xpack-riscv-none-elf-gcc-13.2.0-2/bin}"
GCC="${GCC:-$TC/riscv-none-elf-gcc}"
OBJCOPY="${OBJCOPY:-$TC/riscv-none-elf-objcopy}"

if ! command -v "$GCC" &>/dev/null && ! command -v riscv-none-elf-gcc &>/dev/null && ! command -v riscv32-unknown-elf-gcc &>/dev/null; then
  echo "ERROR: RISC-V GCC toolchain not found!" >&2
  exit 1
fi

if ! command -v "$GCC" &>/dev/null; then
  if command -v riscv-none-elf-gcc &>/dev/null; then
    GCC="riscv-none-elf-gcc"
    OBJCOPY="riscv-none-elf-objcopy"
  elif command -v riscv32-unknown-elf-gcc &>/dev/null; then
    GCC="riscv32-unknown-elf-gcc"
    OBJCOPY="riscv32-unknown-elf-objcopy"
  fi
fi

FLAGS="-O2 -march=rv32im -mabi=ilp32 -nostartfiles -fno-pic -Wl,--no-relax -fno-builtin"
INCLUDES="-I."

echo "Compiling CoreMark for Takshaka..."

ITERATIONS="${1:-100}"
LDSCRIPT="../../sw/link.ld"

"$GCC" $FLAGS $INCLUDES -T "$LDSCRIPT" \
    -DITERATIONS=$ITERATIONS -DFLAGS_STR="\"$FLAGS\"" \
    -DPERFORMANCE_RUN=1 \
    -DMAIN_HAS_NOARGC=1 \
    -DEE_TICKS_PER_SEC="100000000UL" \
    -DMEM_METHOD=MEM_STATIC \
    -DSEED_METHOD=SEED_VOLATILE \
    -DHAS_FLOAT=0 \
    -DHAS_TIME_H=0 \
    -DUSE_CLOCK=0 \
    -DHAS_STDIO=0 \
    -DHAS_PRINTF=0 \
    -DMULTITHREAD=1 \
    -DUSE_PTHREAD=0 \
    start.S \
    core_portme.c \
    core_list_join.c \
    core_main.c \
    core_matrix.c \
    core_state.c \
    core_util.c \
    -o coremark.elf

echo "Generating hex file..."
"$OBJCOPY" -O binary coremark.elf coremark.bin
python3 ../../sw/bin2hex.py coremark.bin coremark.hex 8192
echo "Done. coremark.hex is ready."
