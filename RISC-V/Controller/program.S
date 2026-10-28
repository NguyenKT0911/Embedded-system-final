.section .text
.globl _start

# PASS 49 gui hai ky tu 'P' va '1'
.macro PASS digit
    addi x12, x0, 80
    jal  x1, send_byte
    addi x12, x0, \digit
    jal  x1, send_byte
.endm

_start:
    # UART BASE = 0x10000000
    lui x10, 0x10000

# ====================================
# TEST 1: ARITHMETIC AND LOGIC
# ====================================
    addi x5, x0, 5
    addi x6, x0, 8

    add  x7, x5, x6
    addi x8, x0, 13
    bne  x7, x8, fail1

    sub  x8, x7, x5
    bne  x8, x6, fail1

    xor  x8, x5, x6
    bne  x8, x7, fail1

    or   x8, x5, x6
    bne  x8, x7, fail1

    and  x8, x5, x6
    bne  x8, x0, fail1

    xori x8, x5, 3
    addi x9, x0, 6
    bne  x8, x9, fail1

    ori  x8, x5, 8
    bne  x8, x7, fail1

    andi x8, x7, 8
    bne  x8, x6, fail1

    PASS 49

# ====================================
# TEST 2: SHIFT AND COMPARISON
# ====================================
    addi x14, x0, 2
    addi x9, x0, -16

    slli x8, x5, 2
    addi x13, x0, 20
    bne  x8, x13, fail2

    srli x8, x13, 2
    bne  x8, x5, fail2

    srai x8, x9, 2
    addi x13, x0, -4
    bne  x8, x13, fail2

    sll  x8, x5, x14
    addi x13, x0, 20
    bne  x8, x13, fail2

    srl  x8, x7, x14
    addi x13, x0, 3
    bne  x8, x13, fail2

    sra  x8, x9, x14
    addi x13, x0, -4
    bne  x8, x13, fail2

    slt  x8, x9, x5
    addi x13, x0, 1
    bne  x8, x13, fail2

    sltu x8, x9, x5
    bne  x8, x0, fail2

    slti x8, x9, 0
    bne  x8, x13, fail2

    sltiu x8, x9, 0
    bne  x8, x0, fail2

    PASS 50

# ====================================
# TEST 3: DATA MEMORY
# ====================================
    addi x15, x0, 128

    sw   x7, 0(x15)
    lw   x8, 0(x15)

    bne  x8, x7, fail3

    PASS 51

# ====================================
# TEST 4: BRANCH INSTRUCTIONS
# ====================================
    # BEQ: phai nhay
    beq x5, x5, beq_ok
    jal x0, fail4

beq_ok:
    # BEQ: khong duoc nhay
    beq x5, x6, fail4

    # BNE: phai nhay
    bne x5, x6, bne_ok
    jal x0, fail4

bne_ok:
    # BLT: 5 < 8
    blt x5, x6, blt_ok
    jal x0, fail4

blt_ok:
    # BGE: 8 >= 5
    bge x6, x5, bge_ok
    jal x0, fail4

bge_ok:
    # BLTU: unsigned 5 < 8
    bltu x5, x6, bltu_ok
    jal x0, fail4

bltu_ok:
    # BGEU: unsigned 8 >= 5
    bgeu x6, x5, bgeu_ok
    jal x0, fail4

bgeu_ok:
    PASS 52

# ====================================
# TEST 5: LUI AND AUIPC
# ====================================
    lui x8, 0x10000
    bne x8, x10, fail5

    # Hai lenh AUIPC lien tiep
    # phai cho hai gia tri PC cach nhau 4 byte.
    auipc x18, 0
    auipc x19, 0

    addi x18, x18, 4
    bne  x18, x19, fail5

    PASS 53

# ====================================
# TEST 6: JAL AND JALR
# ====================================
    jal x16, jal_target

after_jal:
    jal x0, fail6

jal_target:
    # Kiem tra link address cua JAL
    la  x19, after_jal
    bne x16, x19, fail6

    # Kiem tra JALR
    la   x18, jalr_target
    jalr x17, 0(x18)

after_jalr:
    jal x0, fail6

jalr_target:
    # Kiem tra link address cua JALR
    la  x19, after_jalr
    bne x17, x19, fail6

    PASS 54

# ====================================
# ALL TESTS COMPLETED
# ====================================
    # Gui 'D' = DONE
    addi x12, x0, 68
    jal  x1, send_byte

halt:
    jal x0, halt

# ====================================
# FAIL HANDLERS
# ====================================
fail1:
    addi x20, x0, 49
    jal x0, fail

fail2:
    addi x20, x0, 50
    jal x0, fail

fail3:
    addi x20, x0, 51
    jal x0, fail

fail4:
    addi x20, x0, 52
    jal x0, fail

fail5:
    addi x20, x0, 53
    jal x0, fail

fail6:
    addi x20, x0, 54
    jal x0, fail

fail:
    # Gui 'F'
    addi x12, x0, 70
    jal  x1, send_byte

    # Gui so thu tu nhom bi loi
    addi x12, x20, 0
    jal  x1, send_byte

    jal x0, halt

# ====================================
# UART TRANSMIT FUNCTION
#
# Input: x12 = byte can gui
# Uses: x10, x11, x12, x1
# ====================================
send_byte:
wait_tx:
    lw   x11, 4(x10)
    andi x11, x11, 1
    beq  x11, x0, wait_tx

    sw   x12, 0(x10)

    jalr x0, 0(x1)