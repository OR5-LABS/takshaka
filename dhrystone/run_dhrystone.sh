#!/usr/bin/env bash
# run_dhrystone.sh — build Dhrystone and run it on Takshaka simulation.
# Usage: ./run_dhrystone.sh [NUMBER_OF_RUNS]
set -euo pipefail
cd "$(dirname "$0")"

RUNS="${1:-2000000}"

echo "Building Dhrystone for simulation (${RUNS} runs)..."
./src/build_dhrystone.sh "${RUNS}"

if [ ! -f ../obj_dir/Vtb_takshaka ]; then
  echo "Building Takshaka simulator with Verilator..."
  cd ..
  verilator --binary --timing --top tb_takshaka -Wno-fatal -Irtl/common -Irtl rtl/common/takshaka_pkg.sv rtl/common/takshaka_alu.sv rtl/common/takshaka_regfile.sv rtl/common/takshaka_muldiv.sv rtl/common/takshaka_csr.sv rtl/common/takshaka_rvc.sv rtl/common/takshaka_immgen.sv rtl/common/takshaka_branch.sv rtl/common/takshaka_decode.sv rtl/common/takshaka_pmp.sv rtl/takshaka_debug.sv rtl/takshaka_core.sv rtl/takshaka_uart.sv rtl/takshaka_soc.sv tb/tb_takshaka.sv
  cd -
fi

echo "Running Dhrystone on Takshaka simulation..."
# cycle budget scales with the run count (about 330 cycles per run, plus setup)
MAXCYC=$(( RUNS * 500 + 20000000 ))
log=$(mktemp)
../obj_dir/Vtb_takshaka +IMEM=src/dhrystone.hex +MAXCYCLES="$MAXCYC" | tee "$log"
# the run must end with the testbench's PASS verdict (tohost = 1)
if grep -qE 'FAIL|TIMEOUT' "$log" || ! grep -q '^\[TB\] PASS' "$log"; then
  rm -f "$log"; echo "Dhrystone: FAIL (no [TB] PASS verdict)"; exit 1
fi
rm -f "$log"
