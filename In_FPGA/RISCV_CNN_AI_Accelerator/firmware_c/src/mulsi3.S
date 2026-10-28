.option norvc
.option norelax
.section .text
.globl __mulsi3
.type __mulsi3, @function
__mulsi3:
    mv a2, a0
    li a0, 0
.Lmul_loop:
    andi a3, a1, 1
    beqz a3, .Lmul_skip
    add a0, a0, a2
.Lmul_skip:
    slli a2, a2, 1
    srli a1, a1, 1
    bnez a1, .Lmul_loop
    ret
.size __mulsi3, .-__mulsi3

