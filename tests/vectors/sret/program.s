.text
.globl _start
_start:
la r5,user
csrw epc,r5
csrw status,zero
sret
user:
li r6,321
scall
li r7,888
