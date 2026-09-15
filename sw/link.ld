/* link.ld — AstraV bare-metal layout.
   .text/.rodata live in IMEM (loaded from the hex). .bss + stack live in DRAM
   (zeroed by the testbench at reset). No initialized .data is used by the test
   programs, so there is no flash->RAM copy and the loadable image is just the
   low IMEM region. */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
  IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 32K
  DRAM (rw)  : ORIGIN = 0x80000000, LENGTH = 32K
}

SECTIONS {
  .text : {
    KEEP(*(.text.init))
    *(.text*)
    *(.rodata*)
    *(.srodata*)
    . = ALIGN(4);
  } > IMEM

  .data : {
    _data_start = .;
    *(.data*)
    *(.sdata*)
    . = ALIGN(4);
    _data_end = .;
  } > DRAM AT > IMEM

  _data_load = LOADADDR(.data);

  .bss (NOLOAD) : {
    _bss_start = .;
    *(.sbss*)
    *(.bss*)
    *(COMMON)
    . = ALIGN(4);
    _bss_end = .;
  } > DRAM

  _end = .;
}
