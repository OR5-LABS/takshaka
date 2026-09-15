    .section .text.init
    .global _start
_start:
    /* Set up stack pointer */
    la sp, _stack_top

    /* Copy .data section from LMA to VMA */
    la a0, _data_lma
    la a1, _data_start
    la a2, _data_end
    bgeu a1, a2, .Ldata_done
.Ldata_loop:
    lw   t0, 0(a0)
    sw   t0, 0(a1)
    addi a0, a0, 4
    addi a1, a1, 4
    bltu a1, a2, .Ldata_loop
.Ldata_done:

    /* Zero .bss section */
    la a0, _bss_start
    la a1, _bss_end
    bgeu a0, a1, .Lbss_done
.Lbss_loop:
    sw   zero, 0(a0)
    addi a0,   a0, 4
    bltu a0,   a1, .Lbss_loop
.Lbss_done:

    /* Jump to main */
    call main

    /* Write tohost to signal sim exit */
    li   t0, 0x20000000
    li   t1, 1
    sw   t1, 0(t0)
.Lhalt:
    j .Lhalt
