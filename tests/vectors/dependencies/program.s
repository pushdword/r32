.text
.globl _start
_start:
li sp,0x1000f000
li r5,0x10000000
li r6,19
sw r6,0(r5)
lw r7,0(r5)
add r8,r7,r6
call twice
wfi
twice:
add a0,r8,r8
ret
