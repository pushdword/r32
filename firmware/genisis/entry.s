# R32 BRAM reset, local stack and firmware handoff ABI.
.text
.globl _start
_start:
    j genisis_r32_entry
genisis_r32_entry:
    csrw status,r0
    csrw scratch,r0
    li sp,0x8000
    la r5,__bss_start
    la r6,__bss_end
.Lfw_zero:
    bgeu r5,r6,.Lfw_enter
    sw r0,0(r5)
    addi r5,r5,4
    j .Lfw_zero
.Lfw_enter:
    la r5,.Lfw_trap
    csrw tvec,r5
    call genisis_r32_reset
    wfi
.Lfw_trap:
    li r5,0xf0000000
    li r6,33
    sb r6,0(r5)
    csrr r3,cause
    csrr r4,epc
    wfi
.globl genisis_hal_enter
genisis_hal_enter:
    mv r5,a0
    mv a0,a1
    fence.i
    jalr r0,r5,0
