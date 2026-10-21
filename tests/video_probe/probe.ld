ENTRY(_start)

SECTIONS
{
    . = 0x10800000;
    .text :
    {
        KEEP(*(.text.start))
        *(.text .text.*)
        *(.rodata .rodata.*)
    }
    .data ALIGN(16) :
    {
        *(.data .data.*)
    }
    .bss ALIGN(16) (NOLOAD) :
    {
        *(.bss .bss.* COMMON)
    }
    /DISCARD/ :
    {
        *(.comment .note.* .eh_frame*)
    }
}
