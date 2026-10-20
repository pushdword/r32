.text
.globl _start
_start:
j good
.word 0xffffffff
sw r0,1(r0)
good:
li r5,123
wfi