/* Real cycle counter makes electrical delays independent of C optimization.
 * All waits also have an independent poll limit if the counter stops. */
#include "pmod.h"
#include "hal.h"

int genisis_pmod_open(struct genisis_pmod *bus, uintptr_t base, uint32_t hz)
{
    bus->base = base;
    bus->hz = hz;
    bus->control = 0;
    if (hz < 1000000u || hz > 100000000u || genisis_hal_read32(base + 32u) != GENISIS_PMOD_ID ||
        genisis_hal_read32(base + 16u) != hz)
        return 0;
    bus->control = genisis_hal_read32(base + 24u) & 1u;
    genisis_hal_write32(base + 24u, bus->control); /* Release both I2C wires. */
    return 1;
}

int genisis_pmod_delay(struct genisis_pmod *bus, unsigned microseconds)
{
    /* Bounded intervals avoid overflow and ambiguity across counter wrap. */
    if (microseconds > 10000u)
        return 0;
    uint32_t cycles = (bus->hz / 1000000u) * microseconds;
    uint32_t first = genisis_hal_read32(bus->base + 36u);
    unsigned budget = 100000u;
    while (genisis_hal_read32(bus->base + 36u) - first < cycles)
        if (!--budget)
            return 0;
    return 1;
}

void genisis_pmod_control(struct genisis_pmod *bus, unsigned scl_low, unsigned sda_low)
{
    bus->control = (bus->control & 1u) | (scl_low ? 2u : 0u) | (sda_low ? 4u : 0u);
    genisis_hal_write32(bus->base + 24u, bus->control);
}

void genisis_pmod_release(struct genisis_pmod *bus)
{
    genisis_pmod_control(bus, 0, 0);
}

void genisis_pmod_zero(void *object, unsigned bytes)
{
    /* Volatile byte stores prevent a libc memset call in freestanding code.
     * Character aliasing permits access to the complete object representation. */
    volatile unsigned char *out = object;
    while (bytes--)
        *out++ = 0;
}
