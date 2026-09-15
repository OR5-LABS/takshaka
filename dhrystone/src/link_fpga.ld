OUTPUT_ARCH(riscv)
ENTRY(_start)

/*
 * link_fpga.ld — Dhrystone 2.1 linker script for the Takshaka FPGA SoC
 *                (Arty A7-100T and similar boards).
 *
 * The FPGA SoC (takshaka_fpga.sv) has a single unified BRAM region:
 *   Address 0x0000_0000 .. (MEM_WORDS*4 - 1)   — default: 32 KB (MEM_WORDS=8192)
 *
 * Unlike the simulation link.ld, .data and .bss MUST NOT be placed at
 * 0x8000_0000: the SoC has no DRAM there and silently discards all writes,
 * causing pointer dereferences to return 0 and corrupt the BRAM text region.
 *
 * Everything — .text, .rodata, .data, .bss, and the stack — lives in the
 * single 32 KB ram region. VMA == LMA for .data, so no copy is needed.
 */

MEMORY {
    ram (rwx) : ORIGIN = 0x00000000, LENGTH = 32K
}

SECTIONS {
    .text : {
        *(.text.init)
        *(.text .text.*)
        *(.rodata .rodata.*)
    } > ram

    .data : ALIGN(4) {
        _data_start = .;
        *(.data .data.*)
        *(.sdata .sdata.*)
        . = ALIGN(4);
        _data_end = .;
    } > ram
    _data_lma = LOADADDR(.data);   /* VMA == LMA; start.S copy loop is a no-op */

    .bss : ALIGN(4) {
        _bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        _bss_end = .;
    } > ram

    . = ALIGN(16);
    . += 0x2000;    /* 8 KB stack */
    _stack_top = .;
}
