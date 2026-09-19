# Takshaka

**Takshaka** is a compact, high-performance **3-stage pipelined RV32IMAC**
processor core. It executes instructions in a classic in-order
fetch / execute / memory-writeback pipeline with full result forwarding (no
load-use stall), and a dynamic branch predictor — delivering strong
per-clock throughput while staying small and easy to reason about.

The core targets embedded and control-plane roles that want more performance
than a minimal multi-cycle core without the area of an application processor:
microcontrollers, real-time controllers, smart peripherals, and FPGA soft
cores.

---

## Highlights

- **ISA:** `RV32IMACB_Zicsr_Zcb_Zbc`: RV32IMAC, the ratified `B` extension (`Zba`, `Zbb`, `Zbs`), `Zbc` carry-less multiply, `Zcb`, `Zicsr`
- **Pipeline:** 3-stage in-order with full W→X forwarding and no load-use stall (only multiply/divide and misaligned accesses stall)
- **Branch Prediction:** 256-entry gshare, 64-entry BTB, and RAS
- **Privilege & Security** (`SECURE` build): Machine and User modes, user-level trap delegation (from the withdrawn `N` extension draft, never ratified; `misa.N` is not set), and 8-region PMP with Smepmp (including machine mode lockdown)
- **Triggers** (both builds): two `Sdtrig` triggers (`mcontrol6` format), execute and load/store address match
- **Memory & Buses:** Hardware misaligned access, native bus, and AXI4-Lite master
- **Debug:** RISC-V external debug via JTAG (Debug Module and JTAG DTM report debug spec 0.13 (`dmstatus.version` = 2))
- **Software & RTOS:** Preemptive FreeRTOS port with UART console
- **Verification:** the official riscv-tests ISA suites (215 pass, 3 skipped with stated reasons), co-simulation of the smoke program against a golden RV32IM ISA model, an RVFI (riscv-formal interface) trace self-check, and self-checking directed tests


---

## Repository layout

```
takshaka/
├── rtl/                 core RTL
│   ├── takshaka_core.sv   3-stage pipeline + predictor + forwarding
│   ├── takshaka_soc.sv    minimal SoC (IMEM/DRAM, CLINT, UART, tohost)
│   ├── takshaka_debug.sv  JTAG DTM + RISC-V Debug Module
│   ├── takshaka_axi_lite.sv  AXI4-Lite master bridge
│   ├── takshaka_uart.sv   UART console peripheral
│   └── common/            shared, pre-verified datapath leaf cells
│                          (ALU, multiply/divide, register file, CSR file,
│                           immediate/branch units, decoder, RVC, PMP)
├── tb/                  testbenches (smoke, RVFI, debug, priv, AXI-Lite, RTOS)
├── tools/              golden ISA model + co-simulation driver
├── programs/           test-program builders
├── sw/                 assembly test programs & bring-up firmware
├── rtos/               FreeRTOS port (kernel, BSP, demo app)
├── fpga/               FPGA SoC + Arty A7
├── docs/               documentation site (MkDocs)
└── build.sh            build & test driver
```

## Requirements

- **Verilator 5+** for simulation
- **Python 3.10+** for the test-program builders and co-simulation
- a RISC-V GCC toolchain (`riscv-none-elf-*`) for `run_isa.sh` and the FPGA firmware; the FreeRTOS demo and the benchmarks also need its C library (newlib), as shipped in the xPack `riscv-none-elf-gcc`
- *(optional)* Vivado for the Arty A7 FPGA flows

## Build & test

```bash
./build.sh          # compile + self-checking smoke test
./build.sh cosim    # + co-simulate against the golden ISA model
./build.sh rvfi     # RVFI (formal interface) self-check
./build.sh zcb      # directed Zcb test + its negative control
./build.sh trig     # trigger tests on the default (M-only) SoC
./build.sh debug    # JTAG / Debug-Module self-check
./build.sh priv     # SECURE config: M/U privilege, user-trap delegation, PMP, Smepmp + trigger tests
./build.sh axi      # AXI4-Lite master BFM test
./build.sh fpga     # FPGA SoC sim (UART banner + LED), needs a RISC-V GCC
./build.sh rtos     # FreeRTOS preemptive multitasking demo, needs a RISC-V GCC with newlib
./build.sh clean
./run_isa.sh        # official riscv-tests ISA suites (default + SECURE builds), needs a RISC-V GCC
./run_tests.sh      # all of the above except rtos, checked against tests/expected.txt
```

Every `build.sh` action and `run_isa.sh` exits non-zero when its testbench
reports a failure, a timeout, a mismatch or an error, or does not print its
PASS verdict. Tools are taken from `PATH`; set `RISCV_TC=/path/to/bin` to use a
specific `riscv-none-elf-*` toolchain.

## Test status

Results of `./run_tests.sh` (Verilator 5.020, RISC-V GCC 13.2), recorded in
`tests/expected.txt`:

| Test | What it checks | Result |
| :--- | :--- | :--- |
| `build.sh sim` | smoke program (ALU, M, branches, loads/stores, CSR, traps) | PASS |
| `build.sh cosim` | smoke program retire-by-retire against the golden RV32IM model | PASS |
| `build.sh rvfi` | RVFI trace invariants over the smoke program | PASS |
| `build.sh zcb` | directed Zcb test; the negative control fails as designed | PASS |
| `build.sh debug` | JTAG DTM + Debug Module: halt, GPR/memory access, resume, single-step | PASS |
| `build.sh trig` | trigger breakpoint/watchpoint tests (hit + miss controls) on the default SoC | PASS |
| `build.sh priv` | 24 directed SECURE-core tests: U-mode traps, PMP load/store/AMO/fetch faults, Smepmp MML, trigger breakpoints/watchpoints, user-trap delegation, `mtvec` mode | 24/24 PASS |
| `build.sh axi` | AXI4-Lite master bridge against a slave BFM, incl. SLVERR | PASS |
| `build.sh fpga` | FPGA SoC simulation: UART banner + LED | PASS |
| `run_isa.sh` | official riscv-tests (see below) | 215 PASS, 3 SKIP |

Run separately (they need a RISC-V GCC with a C library, such as the xPack
`riscv-none-elf-gcc`): `./build.sh rtos` (FreeRTOS demo plus its tick-disabled
negative control: PASS), `coremark/run_coremark.sh` (PASS, 100 iterations) and
`dhrystone/run_dhrystone.sh` (PASS, 2,000,000 runs). These scripts also exit non-zero unless the
testbench reports PASS.

## ISA test results

`./run_isa.sh` builds the official [riscv-tests](https://github.com/riscv-software-src/riscv-tests)
(vendored under `third_party/riscv-tests`, unmodified, with the official
`riscv-test-env` `p` environment) and runs them on the Takshaka SoC testbench
(`tb/tb_takshaka.sv` + `rtl/takshaka_soc.sv`) in two builds: the default
Machine-only core and the `SECURE` core, where the environment runs the
`rv32u*` tests in User mode. Code is linked into IMEM at `0x0`, data into DRAM
at `0x8000_0000`, and a test passes when it writes 1 to `tohost` (`0x2000_0000`).
The testbench is built with `-DTAKSHAKA_IMEM_WRITABLE` because `rv32uc/rvc`
stores into data kept in its code section.

| Suite | Default build | `SECURE` build |
| :--- | :--- | :--- |
| `rv32ui` | 41 PASS, 1 SKIP | 41 PASS, 1 SKIP |
| `rv32um` | 8 PASS | 8 PASS |
| `rv32ua` | 10 PASS | 10 PASS |
| `rv32uc` | 1 PASS | 1 PASS |
| `rv32uzba` | 3 PASS | 3 PASS |
| `rv32uzbb` | 18 PASS | 18 PASS |
| `rv32uzbc` | 3 PASS | 3 PASS |
| `rv32uzbs` | 8 PASS | 8 PASS |
| `rv32mi` | 15 PASS, 1 SKIP | 16 PASS |
| **Total** | **107 PASS, 2 SKIP** | **108 PASS, 1 SKIP** |

Skipped, with the reason printed by `run_isa.sh`:

- `rv32ui/fence_i` (both builds): `Zifencei` is not implemented and not
  claimed. `FENCE.I` executes as a no-op and does not resynchronize instruction
  fetch with earlier stores; run anyway, the test fails.
- `rv32mi/pmpaddr` (default build): the test needs PMP, which only the `SECURE`
  build implements. It passes in the `SECURE` build.

Some `rv32mi` tests check an optional feature only when it is present and pass
without exercising it here: `breakpoint` tests only the type-2 `mcontrol`
trigger (Takshaka implements `mcontrol6`, covered by `build.sh priv`), and
`illegal` skips its Supervisor-mode, vectored-interrupt and virtual-memory
checks because those are not implemented.

## Known limitations

- `Zifencei` is not implemented (`FENCE.I` is a no-op), so code that modifies
  its own instructions is not supported.
- The default SoC drops data-port stores to IMEM; build with
  `-DTAKSHAKA_IMEM_WRITABLE` (or set `IMEM_DATA_WRITE=1`) to allow them.
- Only direct `mtvec` mode is implemented (`mtvec.MODE` reads as 0).
- The `rv32mi` suite does not cover Supervisor mode, virtual memory or vectored
  interrupts, none of which Takshaka implements.
- `run_tests.sh` does not include the FreeRTOS demo or the benchmarks: they
  need a RISC-V GCC with a C library. CI installs the xPack toolchain and runs
  them as separate steps.

## Performance & Benchmarks

Takshaka has been evaluated across industry-standard embedded benchmarks in simulation and bare-metal execution on physical FPGA silicon.

### CoreMark

> Cycle counts are measured in simulation (`coremark/run_coremark.sh`, 100 iterations; `dhrystone/run_dhrystone.sh`, 2,000,000 runs); per-second figures are computed for a 100 MHz clock. The Arty A7 board scripts run at 25 MHz.

| Metric | Result |
| :--- | :--- |
| Cycles / iteration | 341,599 |
| Iterations / Sec (computed for 100 MHz) | 292 |
| CoreMark / MHz | **2.92** |

### Dhrystone v2.1

| Metric | Result |
| :--- | :--- |
| Cycles / iteration | 338 |
| Dhrystones / sec (computed for 100 MHz) | 295,857 |
| DMIPS (computed for 100 MHz) | 168.39 |
| DMIPS / MHz | **1.68** |

---

## Running Benchmarks

> If you are on a fresh clone, you must build the Verilator simulator first by running `./build.sh` from the repository root.

### CoreMark

To compile and run CoreMark in Verilator simulation:

```bash
cd coremark && ./run_coremark.sh
```

To run on physical hardware (Arty A7-100T FPGA @ 25 MHz):
```bash
cd coremark && ./run_coremark_arty_a7.sh
```

### Dhrystone 2.1

To compile and run the industry-standard 2,000,000-iteration Dhrystone benchmark in simulation:

```bash
cd dhrystone && ./run_dhrystone.sh
```

To synthesize, program, and monitor on the Arty A7-100T board (@ 25 MHz):
```bash
cd dhrystone && ./run_dhrystone_arty_a7.sh
```

---

## Configurations

Takshaka ships in two build-time configurations, selected by a parameter /
define:

| Configuration | Privilege | Memory protection | Debug triggers | Use case |
|---------------|-----------|-------------------|----------------|----------|
| **Default**   | Machine only | — | breakpoint / watchpoint | smallest footprint |
| **`SECURE`**  | Machine + User (+ user-trap delegation) | 8-region PMP + Smepmp | breakpoint / watchpoint | isolation & introspection |

Enable the secure configuration with the `SECURE` parameter of `takshaka_core`
/ `takshaka_soc`, or at compile time with `-DTAKSHAKA_SECURE` (read by
`takshaka_soc`).


## License

Released under the [MIT License](LICENSE).
