.text
.globl _start
_start:
li r5,64
csrw scratch,r5
csrr r6,scratch
csrr r7,isa
csrr r8,core_count
wfi