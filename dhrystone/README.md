# Dhrystone on Takshaka

This directory contains a bare-metal **Dhrystone 2.1** port for the **Takshaka RV32IMC** processor. Two run flows are provided: RTL simulation (Verilator) and FPGA hardware (Arty A7-100T).

## Toolchain & Environment

The benchmark is compiled for a 32-bit RISC-V target with the `IMC` extensions (Integer, Multiply/Divide, Compressed instructions). 

- **Compiler**: RISC-V GCC Toolchain (xPack `riscv-none-elf-gcc` v13.2.0)
- **Simulator**: Verilator `v5.050`
- **Architecture**: `RV32IMC`
- **Compiler Flags**:
  
  ```bash
  -O2 -march=rv32imc -mabi=ilp32 -nostartfiles -fno-pic -Wl,--no-relax
  ```

## Performance Results

Takshaka achieves a score of **1.64 DMIPS/MHz** across both simulation and FPGA execution.

### Simulation
- **Environment**: Verilator testbench (`tb_takshaka`)
- **Execution**: 2,000,000 iterations (industry standard)
- **DMIPS**: Varies by simulated clock speed (50 MHz = ~82 DMIPS)
- **DMIPS/MHz**: 1.644

### FPGA (Arty A7-100T)
- **Environment**: Bare-metal execution on the Arty A7 FPGA running at 25 MHz (or 100 MHz).
- **Execution**: 2,000,000 iterations (industry standard)
- **DMIPS/MHz**: 1.644
- **Note**: The core is identical on FPGA and simulation, meaning the IPC (Instructions Per Cycle) and resulting DMIPS/MHz score are exactly identical. Absolute runtime and total DMIPS scale linearly with the physical clock frequency.

---

## Directory layout

```
dhrystone/
├── run_dhrystone.sh            Simulation run script (Verilator)
├── run_dhrystone_arty_a7.sh    FPGA run script (Arty A7-100T)
└── src/
    ├── dhry.h                  Dhrystone 2.1 header (unmodified)
    ├── dhry_1.c                Dhrystone 2.1 main body (unmodified)
    ├── dhry_2.c                Dhrystone 2.1 procedures (unmodified)
    ├── dhry_port.c             Bare-metal RISC-V port (UART + mtime timer)
    ├── start.S                 CRT0: stack setup, BSS clear, _start → main
    ├── link.ld                 Linker script (IMEM @ 0x0, DRAM @ 0x8000_0000)
    └── build_dhrystone.sh      Low-level compiler driver (called by run scripts)
```

## Simulation flow

The simulation script compiles the firmware and runs it through the Verilator
`tb_takshaka` model in one command. Results are printed to stdout — no physical
hardware required.

### Quick start

> [!IMPORTANT]
> Before running the simulation benchmark on a fresh repository, you must first compile the Verilator simulator by running `./build.sh` in the root of the repository.

```bash
# Industry-standard 2 000 000 iterations (default)
./run_dhrystone.sh

# Custom iteration count
./run_dhrystone.sh 5000000
```

### How it works

1. Calls `src/build_dhrystone.sh <RUNS>` which cross-compiles with
   `-DNUMBER_OF_RUNS=<N> -DCLK_FREQ_HZ=50000000 -O2 -march=rv32imc`.
2. Converts the ELF to a `$readmemh`-compatible hex via `sw/bin2hex.py`.
3. Launches `../sim/tb_takshaka +IMEM=src/dhrystone.hex`.

## FPGA flow — Digilent Arty A7-100T

The FPGA script compiles Dhrystone firmware, re-synthesises the bitstream with Vivado, programs the board, and captures the DMIPS result over UART.

### Board connections

| Signal | Pin | Description |
|--------|-----|-------------|
| `CLK100` | E3 | 100 MHz onboard oscillator |
| `ck_rst` | C2 | Active-low reset (pushbutton) |
| `uart_txd_in` | A9 | UART RX into board |
| `uart_rxd_out` | D10 | UART TX out of board |
| JTAG | USB micro-B | Programming via FTDI FT2232H |

UART settings: **115200-8N1**. On Linux the UART device is typically
`/dev/ttyUSB1` (the FT2232H exposes two virtual COM ports; `ttyUSB0` is JTAG,
`ttyUSB1` is UART).

### Quick start

```bash
# Full run (default — industry standard 2M iterations)
./run_dhrystone_arty_a7.sh

# Already have a bitstream, just re-flash and capture
./run_dhrystone_arty_a7.sh --no-synth

# Custom run count or UART device
./run_dhrystone_arty_a7.sh --runs 5000000 --uart-dev /dev/ttyUSB0

# Build only (no board)
./run_dhrystone_arty_a7.sh --no-program
```

## Porting notes

`src/dhry_port.c` provides the three hooks Dhrystone 2.1 requires:

| Symbol | Implementation |
|--------|---------------|
| `uart_putc(char)` | Polls `0x1000_0000` TX-busy bit, then writes |
| `dhr_printf(fmt, …)` | Minimal `%d %u %x %c %s` printf over UART |
| `read_mtime()` | Reads `mtime[31:0]` from CLINT at `0x0200_BFF8` |

The firmware computes elapsed cycles as `mtime_end − mtime_start` (mtime ticks
at `CLK_FREQ_HZ` in the Takshaka SoC) and derives DMIPS/MHz from there.
