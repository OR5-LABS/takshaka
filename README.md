# Takshaka

**Takshaka** is a compact, high-performance **3-stage pipelined RV32IMAC**
processor core. It executes instructions in a classic in-order
fetch / execute / memory-writeback pipeline with full result forwarding, a
load-use interlock, and a dynamic branch predictor — delivering strong
per-clock throughput while staying small and easy to reason about.

The core targets embedded and control-plane roles that want more performance
than a minimal multi-cycle core without the area of an application processor:
microcontrollers, real-time controllers, smart peripherals, and FPGA soft
cores.

---

## Highlights

- **ISA:** RV32IMAC + B (`Zba`/`bb`/`bc`/`bs`), `Zcb`, `Zicsr`
- **Pipeline:** 3-stage in-order with full forwarding & zero load-use stalls
- **Branch Prediction:** Dynamic gshare + BTB + RAS
- **Privilege & Security:** M/U/N modes, 8-region PMP/ePMP, and triggers (`SECURE`)
- **Memory & Buses:** Hardware misaligned access, native bus, and AXI4-Lite master
- **Debug:** RISC-V external debug via JTAG (DTM + DM)
- **Software & RTOS:** Preemptive FreeRTOS port with UART console
- **Verification:** Golden ISA co-simulation, RVFI formal port, and self-checking tests


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

- **Icarus Verilog 12+** (`iverilog` / `vvp`) for simulation
- **Python 3.10+** for the test-program builders and co-simulation
- *(optional)* a RISC-V GCC toolchain to rebuild the assembly test programs
- *(optional)* Vivado for the Arty A7 FPGA flows

## Build & test

```bash
./build.sh          # compile + self-checking smoke test
./build.sh cosim    # + co-simulate against the golden ISA model
./build.sh rvfi     # RVFI (formal interface) self-check
./build.sh debug    # JTAG / Debug-Module self-check
./build.sh priv     # SECURE config: M/U/N + PMP + trigger tests
./build.sh axi      # AXI4-Lite master BFM test
./build.sh rtos     # FreeRTOS preemptive multitasking demo
./build.sh clean
```

## Performance & Benchmarks

Takshaka has been evaluated across industry-standard embedded benchmarks in simulation and bare-metal execution on physical FPGA silicon.

### CoreMark

| Metric | Simulation / FPGA |
| :--- | :--- |
| Cycles / iteration | 341,599 |
| Iterations / Sec (at 100 MHz) | 292 |
| CoreMark / MHz | **2.92** |

### Dhrystone v2.1

| Metric | Simulation / FPGA |
| :--- | :--- |
| Cycles / iteration | 330 |
| Dhrystones / sec (at 100 MHz) | 302,973 |
| DMIPS (at 100 MHz) | 172.43 |
| DMIPS / MHz | **1.72** |

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
| **Default**   | Machine only | — | — | smallest footprint |
| **`SECURE`**  | Machine + User + N | 8-region PMP + ePMP | breakpoint / watchpoint | isolation & introspection |

Enable the secure configuration with the `SECURE` RTL parameter, or at compile
time with `-DTAKSHAKA_SECURE`.

## Documentation

Full documentation — architecture, ISA, memory map, CSRs, branch prediction,
security model, debug, bus integration, FPGA bring-up, and verification —
lives in [`docs/`](docs) and builds into a browsable site with
[MkDocs](https://www.mkdocs.org/):

```bash
pip install -r docs/requirements.txt
mkdocs serve      # http://127.0.0.1:8000
```

## License

Released under the [MIT License](LICENSE).
