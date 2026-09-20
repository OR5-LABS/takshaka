#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo "Building CoreMark for simulation (100 iterations)..."
./src/build_coremark.sh 100

if [ ! -f ../obj_dir/Vtb_takshaka ]; then
  echo "Building Takshaka simulator with Verilator..."
  cd ..
  verilator --binary --timing --top tb_takshaka -Wno-fatal -Irtl/common -Irtl rtl/common/takshaka_pkg.sv rtl/common/takshaka_alu.sv rtl/common/takshaka_regfile.sv rtl/common/takshaka_muldiv.sv rtl/common/takshaka_csr.sv rtl/common/takshaka_rvc.sv rtl/common/takshaka_immgen.sv rtl/common/takshaka_branch.sv rtl/common/takshaka_decode.sv rtl/common/takshaka_pmp.sv rtl/takshaka_debug.sv rtl/takshaka_core.sv rtl/takshaka_uart.sv rtl/takshaka_soc.sv tb/tb_takshaka.sv
  cd -
fi

echo "Running CoreMark on Takshaka simulation..."
log=$(mktemp)
../obj_dir/Vtb_takshaka +IMEM=src/coremark.hex | tee "$log"
# the run must end with the testbench's PASS verdict (tohost = 1)
if grep -qE 'FAIL|TIMEOUT' "$log" || ! grep -q '^\[TB\] PASS' "$log"; then
  rm -f "$log"; echo "CoreMark: FAIL (no [TB] PASS verdict)"; exit 1
fi
rm -f "$log"
