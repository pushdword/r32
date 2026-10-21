/* Parse 32-bit HWDT v1 records within GENISIS_HW_WINDOW.
 * Skip unknown device types and secondary instances. */
#include "hardware.h"
extern unsigned genisis_r32_cpu_hz(void);

int genisis_enumerate(uintptr_t table, struct genisis_platform *p)
{
    p->integrated = p->memory_bytes = p->uart_base = p->uart_baud = 0;
    p->memory_base = 0;
    p->bram_bytes = p->timer_base = p->clock_hz = 0;
    p->video_base = p->spi_base = p->keyboard_base = p->smp_base = p->pmod_base = 0;
    p->core_count = 1;
    if ((table & 3u) || table > UINTPTR_MAX - (GENISIS_HW_WINDOW - 1u))
        return 0;
    uint32_t h[8];
    for (unsigned i = 0; i < 8; ++i)
        h[i] = genisis_hal_read32(table + i * 4u);
    if (h[0] != GENISIS_HW_MAGIC || h[1] != 1u || h[2] < 32u || h[3] < 32u || (h[2] & 3u) ||
        (h[3] & 3u) || h[5] > GENISIS_HW_WINDOW || h[2] > h[5] || !h[4] ||
        h[4] > (h[5] - h[2]) / h[3] || h[2] + h[4] * h[3] != h[5] || !h[6] || h[7])
        return 0;
    struct genisis_platform found = *p;
    found.clock_hz = h[6];
    unsigned seen = 0;
    for (unsigned i = 0; i < h[4]; ++i)
    {
        uint32_t r[8];
        uintptr_t address = table + h[2] + i * h[3];
        for (unsigned j = 0; j < 8; ++j)
            r[j] = genisis_hal_read32(address + j * 4u);
        if (r[0] < GENISIS_HW_CPU || r[0] > GENISIS_HW_PMOD || r[1])
            continue;
        unsigned bit = 1u << r[0];
        if ((seen & bit) || r[2] != 1u ||
            r[7] != (r[0] == GENISIS_HW_PMOD                                 ? 3u
                     : r[0] == GENISIS_HW_SPI || r[0] == GENISIS_HW_KEYBOARD ? 1u
                                                                             : 0u) ||
            (r[3] & 3u) || (r[4] & 3u) || (r[4] && r[3] > UINT32_MAX - (r[4] - 1u)))
            return 0;
        seen |= bit;
        /* Validate the supported board address map before destructive POST. */
        switch (r[0])
        {
        case GENISIS_HW_CPU:
            if (r[3] || r[4] || r[5] != GENISIS_HW_NO_IRQ || r[6] != genisis_r32_cpu_hz())
                return 0;
            found.integrated |= GENISIS_CPU;
            break;
        case GENISIS_HW_BRAM:
            if (r[3] || r[4] < 16384u || r[4] > 65536u || r[5] != GENISIS_HW_NO_IRQ || r[6])
                return 0;
            found.bram_bytes = r[4];
            break;
        case GENISIS_HW_SDRAM:
            if (r[3] != 0x10000000u || r[4] != 0x04000000u || r[5] != GENISIS_HW_NO_IRQ || r[6])
                return 0;
            found.memory_base = r[3];
            found.memory_bytes = r[4];
            found.integrated |= GENISIS_SDRAM;
            break;
        case GENISIS_HW_UART:
            if (r[3] != 0xf0000000u || r[4] != 12u || r[5] != GENISIS_HW_NO_IRQ || !r[6])
                return 0;
            found.uart_base = r[3];
            found.uart_baud = r[6];
            found.integrated |= GENISIS_UART;
            break;
        case GENISIS_HW_TIMER:
            if (r[3] != 0xf0001000u || r[4] != 32u || r[5] != 32u || r[6] != h[6])
                return 0;
            found.timer_base = r[3];
            found.integrated |= GENISIS_TIMER;
            break;
        case GENISIS_HW_VIDEO:
            if (r[3] != 0xf0010000u || (r[4] != 16384u && r[4] != 32768u) ||
                r[5] != GENISIS_HW_NO_IRQ || r[6] != 40000000u)
                return 0;
            found.video_base = r[3];
            found.integrated |= GENISIS_VIDEO;
            break;
        case GENISIS_HW_SPI:
            if (r[3] != 0xf0004000u || r[4] != 32u || r[5] != GENISIS_HW_NO_IRQ || r[6] != h[6])
                return 0;
            found.spi_base = r[3];
            found.integrated |= GENISIS_SPI;
            break;
        case GENISIS_HW_KEYBOARD:
            if (r[3] != 0xf0005000u || r[4] != 32u || r[5] != GENISIS_HW_NO_IRQ ||
                r[6] != 12000000u)
                return 0;
            found.keyboard_base = r[3];
            found.integrated |= GENISIS_KEYBOARD;
            break;
        case GENISIS_HW_SMP:
            if (r[3] != 0xf0006000u || r[4] != 64u || r[5] != 33u || r[6] != 1u)
                return 0;
            found.smp_base = r[3];
            found.core_count = r[6];
            found.integrated |= GENISIS_SMP;
            break;
        case GENISIS_HW_PMOD:
            if (r[3] != 0xf0007000u || r[4] != 64u || r[5] != GENISIS_HW_NO_IRQ || r[6] != h[6])
                return 0;
            found.pmod_base = r[3];
            found.integrated |= GENISIS_PMOD;
            break;
        }
    }
    if ((found.integrated & 7u) != 7u || !found.bram_bytes)
        return 0;
    *p = found; /* Commit the validated device description. */
    return 1;
}
