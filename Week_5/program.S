.section .text
.globl _start

_start:
	#viet chuong trinh o day
	addi x1, x0, 5
	addi x2, x0, 8
	add x3, x1, x2
	sub x4, x2, x1
	addi x12, x0, 100
	sw x3, 0(x12)
	lw x5, 0(x12)
	
	
loop:
	beq x0, x0, loop