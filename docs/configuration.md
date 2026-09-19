# Configuration Reference

Takshaka is configured at build time. The most important switch is the `SECURE`
configuration; individual features can be included or omitted to trade area for
capability.

## Configurations

| Configuration | Privilege | PMP / Smepmp | Debug triggers | Use case |
|---------------|-----------|------------|----------------|----------|
| **Default** | Machine only | — | — | smallest footprint |
| **`SECURE`** | Machine + User (+ user-trap delegation) | 8-region PMP + Smepmp | breakpoint / watchpoint | isolation & introspection |

Enable the secure configuration with the `SECURE` RTL parameter, or at compile
time with `-DTAKSHAKA_SECURE`.

## Always present

- 3-stage in-order pipeline with full forwarding (no load-use stall)
- RV32IMAC + `B` (Zba/Zbb/Zbc/Zbs) + `Zcb`
- gshare + BTB + RAS branch predictor
- hardware misaligned load/store
- machine-mode traps, timers, and interrupts
- RISC-V External Debug (JTAG DTM + Debug Module)
- native memory interface

## Optional / configurable

| Feature | How | Notes |
|---------|-----|-------|
| User mode + user-trap delegation | `SECURE` | M/U privilege; delegation follows the withdrawn `N` draft (never ratified) |
| PMP + Smepmp | `SECURE` | 8 regions, TOR/NA4/NAPOT, `mseccfg` |
| Debug triggers | `SECURE` | `mcontrol6` execute + load/store match |
| AXI4-Lite bus | instantiate `takshaka_axi_lite` | optional; default SoC uses the native interface |
| FreeRTOS | `rtos/` | preemptive RTOS port + demo |

## Build-driver targets

| Target | Meaning |
|--------|---------|
| `sim` | compile + smoke (default) |
| `cosim` | + golden-model co-simulation |
| `rvfi` | RVFI self-check |
| `debug` | JTAG / Debug-Module self-check |
| `priv` | `SECURE`: M/U privilege, user-trap delegation, PMP + trigger tests |
| `axi` | AXI4-Lite master BFM test |
| `rtos` | FreeRTOS preemptive multitasking demo |
| `clean` | remove build artifacts |

See [Getting Started](getting-started.md) to run them.
