#!/usr/bin/env bash
# ==========================================================================
# build_rtos.sh -- build the Takshaka FreeRTOS demo into a $readmemh IMEM hex.
#
# Compiles the FreeRTOS kernel + RISC-V port + Takshaka BSP + demo app, links
# with bsp/takshaka.ld, and emits build/rtos.hex (one 32-bit word per line).
# ==========================================================================
set -euo pipefail
cd "$(dirname "$0")"

# FreeRTOS-Kernel is a fetched dependency (not vendored). Clone the RISC-V-capable
# kernel on first use; only the generic kernel + GCC/RISC-V port are compiled below.
if [ ! -d FreeRTOS-Kernel ]; then
  echo "Fetching FreeRTOS-Kernel (first run)..."
  if command -v git > /dev/null; then
    git clone --depth 1 https://github.com/FreeRTOS/FreeRTOS-Kernel.git
  else
    # no git (e.g. a minimal container): fetch the same branch as a tarball
    python3 - <<'PY'
import io, tarfile, urllib.request, shutil, os
url = "https://github.com/FreeRTOS/FreeRTOS-Kernel/archive/refs/heads/main.tar.gz"
data = urllib.request.urlopen(url, timeout=120).read()
tarfile.open(fileobj=io.BytesIO(data)).extractall(".")
shutil.move("FreeRTOS-Kernel-main", "FreeRTOS-Kernel")
PY
  fi
fi

# RISC-V bare-metal GCC. Tools are taken from PATH; set RISCV_TC=/path/to/bin
# to point at a specific toolchain (e.g. an xpack riscv-none-elf-gcc).
PFX="${RISCV_TC:+$RISCV_TC/}"
GCC="${GCC:-${PFX}riscv-none-elf-gcc}"
OBJCOPY="${OBJCOPY:-${PFX}riscv-none-elf-objcopy}"
OBJDUMP="${OBJDUMP:-${PFX}riscv-none-elf-objdump}"
SIZE="${PFX}riscv-none-elf-size"

K=FreeRTOS-Kernel
PORT=$K/portable/GCC/RISC-V
CHIP=$PORT/chip_specific_extensions/RISCV_MTIME_CLINT_no_extensions

# Optional negative-control build:  build_rtos.sh neg  -> build/rtos_neg.hex
VARIANT="${1:-}"
XDEF=""; OUTBASE="rtos"
if [ "$VARIANT" = "neg" ]; then
  XDEF="-DNEG_NO_TICK"; OUTBASE="rtos_neg"
  echo "== NEGATIVE CONTROL build (tick disabled) =="
fi

mkdir -p build

# rv32imac (Takshaka is RV32IMAC); ilp32 ABI; freestanding; no relax so gp/la
# and the .data LMA stay put for our hand-rolled crt0.
CFLAGS="-march=rv32imac_zicsr_zifencei -mabi=ilp32 -Os -g \
  -ffunction-sections -fdata-sections -fno-builtin -fno-pic \
  -Wall -Wextra -Wno-unused-parameter \
  -I bsp -I app \
  -I $K/include -I $PORT -I $CHIP"

ASFLAGS="-march=rv32imac_zicsr_zifencei -mabi=ilp32 -I $PORT -I $CHIP -I bsp"

SRCS_C="
  $K/tasks.c $K/queue.c $K/list.c $K/timers.c
  $K/portable/MemMang/heap_4.c
  $PORT/port.c
  bsp/bsp.c
  bsp/libc_stubs.c
  app/main.c
"
SRCS_S="
  bsp/start.S
  $PORT/portASM.S
"

OBJS=()
for f in $SRCS_C; do
  o="build/${OUTBASE}_$(echo "$f" | tr '/.' '__').o"
  XF=""
  [ "$f" = "app/main.c" ] && XF="$XDEF"
  "$GCC" $CFLAGS $XF -c "$f" -o "$o"
  OBJS+=("$o")
done
for f in $SRCS_S; do
  o="build/${OUTBASE}_$(echo "$f" | tr '/.' '__').o"
  "$GCC" $ASFLAGS -c "$f" -o "$o"
  OBJS+=("$o")
done

"$GCC" -march=rv32imac_zicsr_zifencei -mabi=ilp32 -nostdlib -nostartfiles \
  -fno-pic -Wl,--no-relax -Wl,--gc-sections \
  -T bsp/takshaka.ld "${OBJS[@]}" -lgcc -o "build/${OUTBASE}.elf"

"$OBJCOPY" -O binary "build/${OUTBASE}.elf" "build/${OUTBASE}.bin"
python ../sw/bin2hex.py "build/${OUTBASE}.bin" "build/${OUTBASE}.hex"

# size report
echo "---- section sizes ----"
"$SIZE" "build/${OUTBASE}.elf" || true
IMEM_BYTES=$(stat -c%s "build/${OUTBASE}.bin" 2>/dev/null || wc -c < "build/${OUTBASE}.bin")
echo "IMEM image: ${IMEM_BYTES} bytes (limit 32768)"
if [ "$IMEM_BYTES" -gt 32768 ]; then
  echo "ERROR: IMEM image exceeds 32 KB"; exit 1
fi
echo "wrote build/${OUTBASE}.hex"
