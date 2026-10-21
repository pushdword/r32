ENTRY(_start)
SECTIONS {
 . = 0;
 .resident : {
  KEEP(*entry.o(.text .text.*))
  *resident.o(.text .text.* .rodata .rodata.*)
  *platform.o(.text .text.* .rodata .rodata.*)
  *enumerate.o(.text .text.* .rodata .rodata.*)
  *post.o(.text .text.* .rodata .rodata.*)
  *video.o(.text .text.* .rodata .rodata.*)
  *sd.o(.text .text.* .rodata .rodata.*)
  *fat_ro.o(.text .text.* .rodata .rodata.*)
  *memory.o(.text .text.* .rodata .rodata.*)
  *recovery.o(.text .text.* .rodata .rodata.*)
  *sd_write.o(.text .text.* .rodata .rodata.*)
 }
 .data ALIGN(16) : { *(.data .data.*) }
 .bss ALIGN(16) (NOLOAD) : { __bss_start = .; *(.bss .bss.* COMMON) . = ALIGN(16); __bss_end = .; }
 ASSERT(__bss_end <= 0x6000, "GUI resident/globals exceed 24KiB; 8KiB stack required")
 . = 0x13f00000;
 .firmware : { __firmware_start = .; KEEP(*(.text.main)) *(.text .text.*) *(.rodata .rodata.*) . = ALIGN(4); __firmware_end = .; }
 ASSERT(main == __firmware_start, "GUI entry must be the start of package")
 ASSERT(__firmware_end <= 0x13f80000, "GUI exceeds its 512KiB SDRAM window")
 /DISCARD/ : { *(.comment .note.* .eh_frame*) }
}
