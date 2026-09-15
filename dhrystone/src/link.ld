OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    imem (rx)  : ORIGIN = 0x00000000, LENGTH = 64K
    dram (rw)  : ORIGIN = 0x80000000, LENGTH = 64K
}

SECTIONS {
    .text : {
        *(.text.init)
        *(.text .text.*)
        *(.rodata .rodata.*)
    } > imem

    .data : {
        . = ALIGN(4);
        _data_start = .;
        *(.data .data.*)
        *(.sdata .sdata.*)
        . = ALIGN(4);
        _data_end = .;
    } > dram AT > imem
    _data_lma = LOADADDR(.data);

    .bss : {
        . = ALIGN(4);
        _bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        _bss_end = .;
    } > dram

    . = ALIGN(16);
    . += 0x2000;   /* 8 KB stack */
    _stack_top = .;
}
