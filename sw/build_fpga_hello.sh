#!/usr/bin/env bash
# build_fpga_hello.sh — assemble the FPGA bring-up demo into firmware.mem
# ($readmemh, one 32-bit word per line) for kavacha_fpga / takshaka_fpga.
set -euo pipefail
cd "$(dirname "$0")"
TC="${RISCV_TC:-}"
PFX="${TC:+$TC/}"
GCC="${GCC:-${PFX}riscv-none-elf-gcc}"
OBJCOPY="${OBJCOPY:-${PFX}riscv-none-elf-objcopy}"

if ! command -v "$GCC" &>/dev/null; then
  if command -v riscv-none-elf-gcc &>/dev/null; then
    GCC="riscv-none-elf-gcc"
    OBJCOPY="riscv-none-elf-objcopy"
  elif command -v riscv32-unknown-elf-gcc &>/dev/null; then
    GCC="riscv32-unknown-elf-gcc"
    OBJCOPY="riscv32-unknown-elf-objcopy"
  else
    echo "ERROR: RISC-V GCC toolchain not found. Set RISCV_TC or GCC env vars." >&2
    exit 1
  fi
fi
OUT="${1:-firmware.mem}"

"$GCC" -march=rv32imc -mabi=ilp32 -nostdlib -nostartfiles -fno-pic \
       -Wl,--no-relax -T fpga_hello.ld fpga_hello.S -o fpga_hello.elf
"$OBJCOPY" -O binary fpga_hello.elf fpga_hello.bin
python bin2hex.py fpga_hello.bin "$OUT"
echo "wrote $OUT"
