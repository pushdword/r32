.text
.globl _start
_start:
li r5,0x10000000
li r6,3
sw r6,1(r5)
li r7,999
wfi