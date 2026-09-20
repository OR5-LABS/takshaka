/* Link script for the official riscv-tests on the Takshaka SoC (rtl/takshaka_soc.sv).
 *
 *   code + read-only data -> IMEM at 0x0000_0000 (reset PC = 0; readable by loads)
 *   tohost                -> 0x2000_0000 (the SoC's tohost store port; not loaded)
 *   data + bss            -> DRAM at 0x8000_0000 (preloaded by tb_takshaka +DRAM=)
 *
 * The official env (riscv-test-env p/riscv_test.h) links everything at
 * 0x8000_0000 in one RAM; Takshaka fetches only from IMEM and the data port
 * cannot write IMEM, so code and data are split across the two memories.
 */
OUTPUT_ARCH("riscv")
ENTRY(_start)
MEMORY
{
  IMEM   (rx)  : ORIGIN = 0x00000000, LENGTH = 32K
  TOHOST (rw)  : ORIGIN = 0x20000000, LENGTH = 4K
  DRAM   (rw)  : ORIGIN = 0x80000000, LENGTH = 32K
}
SECTIONS
{
  .text.init : { *(.text.init) } > IMEM
  .text      : { *(.text) *(.text.*) } > IMEM
  .rodata    : { *(.rodata) *(.rodata.*) *(.srodata*) } > IMEM
  .tohost (NOLOAD) : { *(.tohost) } > TOHOST
  .data      : { *(.data) *(.data.*) *(.sdata) *(.sdata.*) } > DRAM
  .bss       : { *(.bss) *(.bss.*) *(.sbss) *(.sbss.*) *(COMMON) } > DRAM
  _end = .;
}
