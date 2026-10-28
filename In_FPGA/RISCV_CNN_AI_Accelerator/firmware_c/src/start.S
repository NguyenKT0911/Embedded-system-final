.option norvc
.option norelax
.section .text.start
.globl _start
.type _start, @function
_start:
    la sp, __stack_top
    /* .data/.rodata are written into DMEM by the UART bootloader. */
    la t1, __bss_start
    la t2, __bss_end
.Lclear_bss:
    bgeu t1, t2, .Lcall_main
    sw zero, 0(t1)
    addi t1, t1, 4
    j .Lclear_bss
.Lcall_main:
    call main
.Lhalt:
    j .Lhalt
.size _start, .-_start

