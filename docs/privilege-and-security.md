# Privilege & Security

Takshaka runs in **Machine mode** by default. The **`SECURE`** configuration
adds a full privilege split and memory protection, turning the core into a small
isolation-capable processor suitable for trusted control planes.

## Privilege modes (`SECURE`)

- **Machine (M)** — full access; the reset mode and trap-handling mode.
- **User (U)** — reduced privilege for application code; M-only CSR access and
  privileged instructions trap to Machine mode.
- **N (user traps)** — selected exceptions can be *delegated* to User mode via
  `medeleg`, handled through the user trap CSRs (`utvec`/`uepc`/`ucause`/…) and
  returned with `URET`, all without leaving User mode.

`mret` drops to the privilege recorded in `mstatus.MPP`; a U-mode `ecall`
returns to Machine mode with cause 8.

## Physical Memory Protection (PMP)

The `SECURE` core includes an **8-region PMP**:

- **Matching:** TOR (top-of-range), NA4, and NAPOT.
- **Permissions:** read / write / execute, checked on instruction fetch and on
  load/store *after* address generation.
- **Locking:** locked entries apply to Machine mode too.
- **Smepmp (`mseccfg`):** enhanced-PMP semantics (Machine-mode whitelisting,
  rule-lock bypass) for a hardened memory model.

A U-mode access that violates a PMP region raises a precise access fault
(instruction = cause 1, load = cause 5, store/AMO = cause 7) with the faulting
address in `mtval`; the Machine handler can inspect and recover.

## What the tests prove

The `build.sh priv` target runs directed tests that demonstrate, each with a
load-bearing negative control:

- entering User mode and returning via `ecall` (correct cause);
- a U-mode M-CSR access trapping as illegal;
- a PMP store violation and an instruction-fetch violation faulting precisely,
  then recovering;
- an `N`-delegated user trap vectoring to `utvec` and returning with `URET`.

See [Debug](debug.md) for the hardware trigger (breakpoint/watchpoint) support,
which shares the `SECURE` build.
