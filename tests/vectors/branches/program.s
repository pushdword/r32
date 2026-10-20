.text
.globl _start
_start:
li r5,12
li r6,0
loop:
addi r6,r6,1
blt r6,r5,loop
beq r6,r5,done
.word 0xffffffff
done:
call other
wfi
other:
add r8,r6,r5
ret