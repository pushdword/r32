.section .text.start
.global _start
_start:
    li r2,0x10810000
    jal r1,main
.Lhalt:
    wfi
    j .Lhalt
