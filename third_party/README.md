# third_party

## riscv-tests/

A subset of the official RISC-V ISA tests, used by `run_isa.sh`.

- `riscv-tests/isa/`: from https://github.com/riscv-software-src/riscv-tests,
  commit `34e6b6d1e7936b526075432fb730d89148623484`. Only the suites Takshaka
  claims are kept (`rv32ui`, `rv32um`, `rv32ua`, `rv32uc`, `rv32uzba`,
  `rv32uzbb`, `rv32uzbc`, `rv32uzbs`, `rv32mi`), plus the `rv64*` sources the
  RV32 tests `#include`, and `isa/macros/scalar/test_macros.h`. The files are
  unmodified.
- `riscv-tests/env/`: from https://github.com/riscv/riscv-test-env, commit
  `6de71edb142be36319e380ce782c3d1830c65d68` (the submodule commit pinned by the
  riscv-tests commit above): `encoding.h` and `p/riscv_test.h`, unmodified.
- `riscv-tests/LICENSE`: the BSD license that covers both repositories (the two
  LICENSE files are identical).

## takshaka-isa/

`link.ld`: the Takshaka-specific link script (written for this repository) that
places the tests on the Takshaka SoC memory map. See `run_isa.sh`.
