/* R32 HAL for the shared Genisis C POST/video/SD modules. */
#include "hal.h"
#include "hardware.h"
#include "video.h"
static struct genisis_platform platform = {.name = "R32 Tang25K board"};
static struct genisis_cpu_description cpu;

unsigned genisis_r32_cpu_hz(void)
{
    unsigned v;
    __asm__ volatile("csrr %0,cpu_hz" : "=r"(v));
    return v;
}

const struct genisis_platform *genisis_hal_platform(void)
{
    return genisis_enumerate(0xf0002000u, &platform) ? &platform : 0;
}

const struct genisis_cpu_description *genisis_hal_cpu_description(void)
{
    const char *name = "R32 six-stage ISA v1";
    for (unsigned i = 0; i < 32; i++)
    {
        cpu.name[i] = *name;
        if (*name)
            name++;
    }
    unsigned isa;
    __asm__ volatile("csrr %0,isa" : "=r"(isa));
    cpu.version = isa & 65535;
    cpu.model = cpu.revision = 1;
    cpu.bits = cpu.address_bits = 32;
    cpu.forms = 56;
    cpu.features = isa & 0xffff0000u;
    return &cpu;
}

uint32_t genisis_hal_read32(uintptr_t a)
{
    return *(volatile uint32_t *)a;
}

void genisis_hal_write32(uintptr_t a, uint32_t v)
{
    *(volatile uint32_t *)a = v;
}

void genisis_hal_write8(uintptr_t a, unsigned char v)
{
    *(volatile unsigned char *)a = v;
}

int genisis_hal_get_byte(unsigned bounded)
{
    unsigned budget = 1000000;
    while (!(genisis_hal_read32(0xf0000004u) & 2))
        if (bounded && !--budget)
            return -1;
    return genisis_hal_read32(0xf0000000u) & 255;
}

void genisis_hal_putc(unsigned char v)
{
    while (!(genisis_hal_read32(0xf0000004u) & 1))
    {
    }
    genisis_hal_write8(0xf0000000u, v);
    genisis_video_putc(v);
}

void genisis_hal_puts(const char *s)
{
    while (*s)
        genisis_hal_putc((unsigned char)*s++);
}

void genisis_hal_flush(void)
{
    while (!(genisis_hal_read32(0xf0000004u) & 1))
    {
    }
}

int genisis_hal_check_cpu(void)
{
    volatile unsigned a = 84, b = 7;
    unsigned x = a, y = b;
    return x + y == 91 && x - y == 77 && x * y == 588 && x / y == 12 && x % y == 0;
}

int genisis_hal_check_uart(void)
{
    unsigned s = genisis_hal_read32(0xf0000004u);
    return (s & ~3u) == 0 && (s & 1u);
}

int genisis_hal_check_timer(void)
{
    return genisis_hal_read32(platform.timer_base + 24) == platform.clock_hz &&
           genisis_hal_read32(platform.timer_base) == 0 &&
           genisis_hal_read32(platform.timer_base + 16) == 0;
}
