# Verification

Takshaka is verified with a layered flow — from quick self-checking smoke tests
to lock-step co-simulation against an independent golden model and a formal
interface.

## Self-checking tests

Every testbench is self-checking: it loads a program, runs it, and asserts an
expected result, signalling PASS/FAIL through the `tohost` handshake. The
directed programs (privilege, PMP, Smepmp, triggers, user-trap delegation,
`Zcb`) mostly pair a positive test with a **load-bearing negative control** (for
example `ustore_fault` / `ustore_ok`), so a
check that silently stops working is caught.

## Golden co-simulation

`build.sh cosim` runs the smoke program on the RTL **and** on an independent
golden **RV32IM ISA model** (`tools/golden_rv32im.py`), comparing the committed
instruction stream retire-by-retire (PC, instruction, register writes). Any
divergence is reported at the first mismatching instruction.

```
[cosim] MATCH — retires identical. RTL is ISA-correct.
```

## RVFI (RISC-V Formal Interface)

`build.sh rvfi` exposes an RVFI retirement port and checks the standard formal
invariants over a real run: instruction-order monotonicity, `x0` always zero,
PC continuity (each `pc_rdata` equals the previous `pc_wdata`), and no unknown
(X) bits in the retired instruction word.

## Debug-Module self-check

`build.sh debug` halts the core over the Debug Module, reads and writes a GPR,
resumes, and confirms the program continues with the debug-written value.

## Official ISA tests

`run_isa.sh` builds the official riscv-tests suites for the ISA Takshaka claims
(`rv32ui`, `rv32um`, `rv32ua`, `rv32uc`, `rv32uzba`, `rv32uzbb`, `rv32uzbc`,
`rv32uzbs`, `rv32mi`) from `third_party/riscv-tests` and runs each one on the
SoC testbench, in the default build and in the `SECURE` build. It prints one
PASS/FAIL/SKIP line per test and a total, and exits non-zero on any failure.
Current result: 215 PASS, 0 FAIL, 3 SKIP (each skip is printed with its
reason; see the README).

## RTOS integration test

`build.sh rtos` boots a real **FreeRTOS** image on the SoC and asserts a
multi-task transcript (queue + semaphore + preemptive timer tick), with a
negative control that disables the tick and confirms preemption is required.

## Performance

CoreMark (`coremark/run_coremark.sh`: `-O2 -march=rv32im`, 100 iterations) run
on the RTL (no caches) measures **2.92 CoreMark/MHz**.
