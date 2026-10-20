.text
.globl _start
_start:
li sp,0x10008000
li t0,0x10009000
csrw scratch,t0
csrrw sp,scratch,sp
csrr t1,scratch
csrrw sp,scratch,sp
csrr t2,scratch
wfi