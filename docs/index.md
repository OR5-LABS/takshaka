# Takshaka

**Takshaka** is a compact, high-performance **3-stage pipelined RV32IMAC**
processor core. It runs a classic in-order fetch / execute / memory-writeback
pipeline with full result forwarding (no load-use stall) and a
dynamic branch predictor — giving strong per-clock throughput in a small,
readable design.

It is built for embedded and control-plane roles that want more performance
than a minimal multi-cycle core without the area of an application processor:
microcontrollers, real-time controllers, smart peripherals, and FPGA soft
cores.

## What you get

- **RV32IMAC** base, plus the **`B`** bit-manipulation set (`Zba`/`Zbb`/`Zbc`/`Zbs`)
  and **`Zcb`** code-size instructions, with `Zicsr`.
- A **3-stage in-order pipeline** with full forwarding and no load-use stall.
- A **dynamic branch predictor** — gshare direction predictor + BTB + return
  address stack.
- Optional **M/U privilege** with user-trap delegation and an **8-region PMP** (with Smepmp)
  in the `SECURE` configuration, and hardware **debug triggers** in both builds.
- Hardware **misaligned** load/store support.
- **RISC-V External Debug** (JTAG DTM + Debug Module).
- An **AXI4-Lite** bus wrapper.
- A ready-to-run **FreeRTOS** port.
- A deep **verification** flow: self-checking tests, golden-model
  co-simulation, RVFI, a Debug-Module self-check, and the official
  riscv-tests ISA suites.
- **2.92 CoreMark/MHz** on RTL (no caches).

## Where to start

- New here? Read [Getting Started](getting-started.md) to build and run the
  self-checking tests.
- Want the microarchitecture? See [Architecture](architecture.md) and
  [Branch Prediction](branch-prediction.md).
- Integrating it into an SoC? See [Memory Map](memory-map.md),
  [Bus Integration](bus-integration.md), and [Debug](debug.md).

## License

Takshaka is released under the [MIT License](https://opensource.org/licenses/MIT).
