# Branch Prediction

Takshaka has a **dynamic branch predictor** in the fetch stage. Because branch
resolution otherwise costs a pipeline bubble on every taken branch, prediction
is the single largest contributor to the core's throughput (and the main reason
it reaches 2.92 CoreMark/MHz, measured with `coremark/run_coremark.sh`).

## Components

- **BTB — Branch Target Buffer.** A direct-mapped table that remembers the
  targets of previously-taken control-flow instructions, so the target is known
  in the fetch stage. The index is **halfword-granular** (it includes `pc[1]`)
  so compressed (16-bit) instructions do not alias in the BTB.
- **gshare direction predictor.** A table of 2-bit saturating counters indexed
  by the fetch PC XOR-ed with a global branch-history register, predicting
  taken / not-taken for conditional branches.
- **RAS — Return Address Stack.** A small stack pushed on calls
  (`jal`/`jalr` writing `x1`/`x5`) and popped on returns, so function returns
  are predicted accurately without polluting the BTB.

## Operation

On each fetch, the predictor produces a next-PC. A predicted-taken branch
redirects the front end in the same cycle. When the branch actually resolves in
the execute stage:

- a **correct** prediction costs nothing — the pipeline flows;
- a **misprediction** flushes the wrongly-fetched instructions, redirects the
  front end to the correct PC, and updates the predictor tables and global
  history.

Prediction is a pure performance optimisation: mispredicts are always corrected,
so architectural results are identical with or without the predictor.

## Verification

The predictor is exercised by the smoke and CoreMark workloads and is covered by
the golden-model co-simulation and the RVFI self-check — the committed
instruction stream is identical to the golden model regardless of prediction
outcomes. See [Verification](verification.md).
