.text
.globl _start
_start:
li r5,0x10000000
li r6,42
lr.w r7,(r5)
sc.w r8,r5,r6
sc.w r9,r5,r6
lr.w r10,(r5)
sw r6,4(r5)
sc.w r11,r5,r6
wfi