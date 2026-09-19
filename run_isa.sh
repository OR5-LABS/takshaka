#!/usr/bin/env bash
# ============================================================================
# run_isa.sh — build and run the OFFICIAL riscv-tests ISA suites on the Takshaka
# SoC testbench (tb/tb_takshaka.sv + rtl/takshaka_soc.sv), in two builds:
#
#   default : the default core (Machine mode only)
#   secure  : the SECURE core (-DTAKSHAKA_SECURE: M/U privilege + PMP); the
#             official env drops rv32u* tests to User mode with mret here.
#
# Sources: third_party/riscv-tests (unmodified official tests + env). The tests
# are linked with third_party/takshaka-isa/link.ld: code at IMEM 0x0, tohost at
# 0x2000_0000, data at DRAM 0x8000_0000 (preloaded with +DRAM=). A test passes
# when it writes 1 to tohost; any other value (or no write before the cycle
# budget) is a failure.
#
#   ./run_isa.sh                     all suites, both builds
#   ./run_isa.sh rv32ui rv32mi       only these suites (both builds)
#   CONFIGS=default ./run_isa.sh     only the default build
#
# Prints one PASS/FAIL/SKIP line per test and a total; exits non-zero on any
# failure (or if nothing ran).
# ============================================================================
set -uo pipefail
cd "$(dirname "$0")"
VRL="${VERILATOR:-verilator}"
PFX="${RISCV_TC:+$RISCV_TC/}"
GCC="${GCC:-${PFX}riscv-none-elf-gcc}"
OBJCOPY="${OBJCOPY:-${PFX}riscv-none-elf-objcopy}"
PY="$(command -v python3 || command -v python)"
RT=third_party/riscv-tests
LD=third_party/takshaka-isa/link.ld
SUITES="${*:-rv32ui rv32um rv32ua rv32uc rv32uzba rv32uzbb rv32uzbc rv32uzbs rv32mi}"
CONFIGS="${CONFIGS:-default secure}"
OUT=build/isa
mkdir -p "$OUT"

# -march per suite, as in the official riscv-tests isa/Makefile.
march() {
  case "$1" in
    rv32uc)     echo rv32imac_zicsr_zifencei ;;
    rv32uzb*)   echo rv32ima_zicsr_zifencei_zba_zbb_zbc_zbs ;;
    *)          echo rv32ima_zicsr_zifencei ;;
  esac
}

# Tests that cannot run on Takshaka, with the reason. Checked before building;
# each is reported as SKIP (never silently dropped).
skip_reason() {  # $1 = config, $2 = suite/test
  case "$1:$2" in
    *:rv32ui/fence_i)
      echo "Zifencei is not implemented (not claimed): FENCE.I executes as a no-op and does not resynchronize instruction fetch with earlier stores" ;;
    default:rv32mi/pmpaddr)
      echo "needs PMP, which only the SECURE build implements (run in the secure build)" ;;
  esac
}

C=rtl/common; R=rtl
CELLS=( "$C/takshaka_pkg.sv" "$C/takshaka_alu.sv" "$C/takshaka_regfile.sv"
  "$C/takshaka_muldiv.sv" "$C/takshaka_csr.sv" "$C/takshaka_rvc.sv"
  "$C/takshaka_immgen.sv" "$C/takshaka_branch.sv" "$C/takshaka_decode.sv"
  "$C/takshaka_pmp.sv" )

build_sim() {  # $1 = config
  # IMEM_WRITABLE: the official tests keep some data in their code section
  # (rv32uc/rvc stores to it); the default SoC drops data-port stores to IMEM.
  local def="-DTAKSHAKA_IMEM_WRITABLE"
  [ "$1" = secure ] && def="$def -DTAKSHAKA_SECURE"
  echo "Building the $1 Takshaka SoC testbench..."
  mkdir -p "sim/isa_$1"
  "$VRL" --binary -j 0 -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC --timescale 1ns/1ps \
    --Mdir "sim/isa_$1" -o tb_takshaka $def -I"$C" -I"$R" \
    "${CELLS[@]}" "$R/takshaka_debug.sv" "$R/takshaka_core.sv" "$R/takshaka_uart.sv" \
    "$R/takshaka_soc.sv" tb/tb_takshaka.sv > "$OUT/build_$1.log" 2>&1 \
    || { echo "  build of the $1 testbench failed (see $OUT/build_$1.log)"; return 1; }
}

pass=0; fail=0; skip=0; failed=""
for cfg in $CONFIGS; do
  if ! build_sim "$cfg"; then fail=$((fail+1)); failed="$failed $cfg(build)"; continue; fi
  for s in $SUITES; do
    for src in $RT/isa/$s/*.S; do
      [ -f "$src" ] || { echo "  no sources for suite $s"; fail=$((fail+1)); failed="$failed $s(missing)"; continue; }
      t=$(basename "$src" .S); name="$s/$t"; o="$OUT/$cfg/$s"; mkdir -p "$o"
      why=$(skip_reason "$cfg" "$name")
      if [ -n "$why" ]; then
        printf "  %-7s %-28s SKIP (%s)\n" "$cfg" "$name" "$why"; skip=$((skip+1)); continue
      fi
      if ! "$GCC" -march="$(march "$s")" -mabi=ilp32 -static -mcmodel=medany -fvisibility=hidden \
           -nostdlib -nostartfiles -fno-pic -Wl,--no-relax \
           -I "$RT/env/p" -I "$RT/isa/macros/scalar" -T "$LD" "$src" -o "$o/$t.elf" \
           > "$o/$t.cc.log" 2>&1; then
        printf "  %-7s %-28s FAIL (build error, see %s)\n" "$cfg" "$name" "$o/$t.cc.log"
        fail=$((fail+1)); failed="$failed $cfg:$name"; continue
      fi
      "$OBJCOPY" -O binary -j .text.init -j .text -j .rodata "$o/$t.elf" "$o/$t.imem.bin"
      "$OBJCOPY" -O binary -j .data "$o/$t.elf" "$o/$t.dram.bin"
      "$PY" sw/bin2hex.py "$o/$t.imem.bin" "$o/$t.imem.hex" > /dev/null
      dram=""
      if [ -s "$o/$t.dram.bin" ]; then
        "$PY" sw/bin2hex.py "$o/$t.dram.bin" "$o/$t.dram.hex" > /dev/null
        dram="+DRAM=$o/$t.dram.hex"
      fi
      "sim/isa_$cfg/tb_takshaka" +IMEM="$o/$t.imem.hex" $dram +MAXCYCLES=500000 \
        > "$o/$t.sim.log" 2>&1
      th=$(grep -oE "tohost write: 0x[0-9a-f]+" "$o/$t.sim.log" | head -1 | sed 's/.*0x//')
      if [ "$th" = "00000001" ]; then
        printf "  %-7s %-28s PASS\n" "$cfg" "$name"; pass=$((pass+1))
      else
        if [ -n "$th" ]; then
          code=$((16#$th)); why="tohost=0x$th, failing TESTNUM $((code >> 1))"
        else
          why="no tohost write within the cycle budget"
        fi
        printf "  %-7s %-28s FAIL (%s)\n" "$cfg" "$name" "$why"
        fail=$((fail+1)); failed="$failed $cfg:$name"
      fi
    done
  done
done
echo "==== ISA: $pass passed, $fail failed, $skip skipped (of $((pass+fail+skip))) ===="
if [ "$fail" -ne 0 ]; then echo "FAILED:$failed"; exit 1; fi
[ "$pass" -gt 0 ] || { echo "no tests ran"; exit 1; }
exit 0
