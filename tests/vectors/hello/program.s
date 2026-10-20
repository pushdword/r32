# R32 reference-system UART demo.
.text
.globl _start
_start:
    li sp, 0x13eff000
    li t0, 0xf0000000
    la t1, message
loop:
    lbu t2, 0(t1)
    beq t2, zero, done
    sb t2, 0(t0)
    addi t1, t1, 1
    j loop
done:
    wfi
.rodata
message:
    .asciz "R32 virtual boot OK\n"
