.text
.globl _start
_start:
li r5,0x10000000
li r6,0xdeadbeef
sw r6,0(r5)
lb r7,0(r5)
lbu r8,1(r5)
lh r9,2(r5)
lhu r10,2(r5)
li r11,0x43
sb r11,1(r5)
sh r11,2(r5)
lw r12,0(r5)
wfi