# Control & Status Registers

Takshaka implements the machine-mode CSRs required for trap handling, timers,
and identification, plus the user-trap (`N` draft) and protection CSRs in the
`SECURE` configuration.

## Machine-mode CSRs

| CSR | Purpose |
|-----|---------|
| `misa` | ISA identification (RV32 + I/M/A/C + B; U when `SECURE`; N is not set) |
| `mstatus` | global interrupt-enable, previous privilege (`MPP`), `MPRV` |
| `mtvec` | machine trap-vector base |
| `mepc` | machine exception PC |
| `mcause` | machine trap cause |
| `mtval` | machine trap value (faulting address / instruction) |
| `mie` / `mip` | interrupt-enable / interrupt-pending |
| `mscratch` | scratch register for trap handlers |
| `mcycle` / `minstret` | cycle and retired-instruction counters |
| `mvendorid` / `marchid` / `mimpid` / `mhartid` | identification |

## User-trap (`N`) CSRs — `SECURE`

When the `N` user-trap extension is enabled, the corresponding user-level trap
CSRs are provided: `ustatus`, `uie`, `uip`, `utvec`, `uepc`, `ucause`, `utval`,
`uscratch`, together with `medeleg` / `mideleg` for delegating traps to User
mode and the `URET` instruction. See
[Privilege & Security](privilege-and-security.md).

## Protection CSRs — `SECURE`

The 8-region PMP is configured through the standard `pmpcfg0..3` and
`pmpaddr0..15` CSRs, with `mseccfg` for the Smepmp (enhanced PMP) rules.

## Debug-trigger CSRs — `SECURE`

Hardware triggers use `tselect`, `tdata1` (`mcontrol6`), `tdata2`, and `tinfo`.
See [Debug](debug.md).

## Access rules

CSRs enforce standard privilege and read/write-legality checks: an access to a
machine-mode CSR from User mode, or a write to a read-only CSR, raises an
illegal-instruction exception.
