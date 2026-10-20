.text
.globl _start
_start:
li r5,0x90000000
lw r6,0(r5)
li r7,777
wfi