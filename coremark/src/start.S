    .section .text.init, "ax"
    .globl _start
_start:
    li   sp, 0x80008000        /* top of 32 KB DRAM */
    li   gp, 0

    /* Copy .data from flash (IMEM) to RAM (DRAM) */
    la a0, _data_load
    la a1, _data_start
    la a2, _data_end
    bge a1, a2, 2f
1:  lw t0, 0(a0)
    sw t0, 0(a1)
    addi a0, a0, 4
    addi a1, a1, 4
    blt a1, a2, 1b
2:
    /* Zero .bss */
    la a0, _bss_start
    la a1, _bss_end
    bge a0, a1, 4f
3:  sw zero, 0(a0)
    addi a0, a0, 4
    blt a0, a1, 3b
4:

    call main
    li   t1, 0x20000000        /* tohost address */
    li   t2, 1
    beqz a0, 1f                /* main() == 0 → PASS (tohost = 1) */
    li   t2, 2                 /* main() != 0 → FAIL (tohost = 2) */
1:  sw   t2, 0(t1)
2:  j    2b
