/* Firmware HAL: register layouts live in the board backend, not in POST.
 * This is an internal C interface, not a new kernel ABI or firmware service ABI. */
#ifndef GENISIS_HAL_H
#define GENISIS_HAL_H
#include <stdint.h>

enum genisis_component
{
    GENISIS_CPU = 1u,
    GENISIS_UART = 2u,
    GENISIS_SDRAM = 4u,
    GENISIS_TIMER = 8u,
    GENISIS_VIDEO = 16u,
    GENISIS_SPI = 32u,
    GENISIS_KEYBOARD = 64u,
    GENISIS_SMP = 128u,
    GENISIS_PMOD = 256u
};

struct genisis_platform
{
    const char *name;
    uint32_t integrated; /* Bitstream capabilities before runtime device probing. */
    uintptr_t memory_base;
    uint32_t memory_bytes, uart_base, uart_baud;
    uint32_t bram_bytes, timer_base, clock_hz;
    uint32_t video_base, spi_base, keyboard_base, smp_base, core_count, pmod_base;
};

/* CPU identity and capabilities used by POST and setup.
 * Feature names label the capability bits. */
struct genisis_cpu_description
{
    char name[32];
    uint32_t version, model, revision, bits, address_bits, forms, features, properties;
};
const struct genisis_cpu_description *genisis_hal_cpu_description(void);
const struct genisis_platform *genisis_hal_platform(void);
uint32_t genisis_hal_read32(uintptr_t address);
void genisis_hal_write32(uintptr_t address, uint32_t value);
void genisis_hal_write8(uintptr_t address, unsigned char value);
int genisis_hal_get_byte(unsigned bounded);
void genisis_hal_putc(unsigned char value);
void genisis_hal_puts(const char *text);
void genisis_hal_flush(void);
int genisis_hal_check_cpu(void);
int genisis_hal_check_uart(void);
int genisis_hal_check_timer(void);
_Noreturn void genisis_hal_enter(uintptr_t entry, const void *info);
#endif
