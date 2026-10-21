/* Experimental SoC hardware description v1: 32-bit little-endian words.
 * This describes controllers, not removable devices or POST results. */
#ifndef GENISIS_HARDWARE_H
#define GENISIS_HARDWARE_H
#include "hal.h"
#define GENISIS_HW_BASE ((uintptr_t)0xf0002000u)
#define GENISIS_HW_MAGIC 0x54445748u /* Bytes HWDT. */
#define GENISIS_HW_WINDOW 4096u
#define GENISIS_HW_NO_IRQ UINT32_MAX

enum genisis_hw_type
{
    GENISIS_HW_CPU = 1,
    GENISIS_HW_BRAM = 2,
    GENISIS_HW_SDRAM = 3,
    GENISIS_HW_UART = 4,
    GENISIS_HW_TIMER = 5,
    GENISIS_HW_VIDEO = 6,
    GENISIS_HW_SPI = 7,
    GENISIS_HW_KEYBOARD = 8,
    GENISIS_HW_SMP = 9,
    GENISIS_HW_PMOD = 10
};

/* Header: magic, version, header_bytes, record_bytes, count, total_bytes,
 * clock_hz, reserved=0. Record: type, instance, interface_version, base,
 * bytes, irq (or NO_IRQ), parameter0, parameter1. No C struct cast of MMIO. */
int genisis_enumerate(uintptr_t table, struct genisis_platform *platform);
#endif
