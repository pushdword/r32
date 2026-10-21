/* Power-on diagnostics using HAL access to CPU and board hardware. */
#include "post.h"

static void observe(const struct genisis_post_options *o, unsigned phase, uint32_t done,
                    uint32_t total)
{
    if (o && o->observe)
        o->observe(phase, done, total);
}

static int failure(struct genisis_post_result *r, uint32_t error, uintptr_t address,
                   uint32_t expected, uint32_t actual)
{
    r->error = error;
    r->address = address;
    r->expected = expected;
    r->actual = actual;
    return 0;
}

static int memory_post(const struct genisis_platform *p, struct genisis_post_result *r,
                       const struct genisis_post_options *o)
{
    uintptr_t addresses[32];
    unsigned count = 1;
    addresses[0] = p->memory_base;
    observe(o, GENISIS_PHASE_DATA, 0, 64);
    /* Walking ones AND zeros cover all 32 data bits, hence both SDRAM beats.
     * The first write waits for the controller's existing initialization FSM. */
    for (unsigned bit = 0; bit < 32; ++bit)
    {
        for (unsigned inverse = 0; inverse < 2; ++inverse)
        {
            uint32_t wanted = 1u << bit;
            if (inverse)
                wanted = ~wanted;
            genisis_hal_write32(p->memory_base, wanted);
            uint32_t got = genisis_hal_read32(p->memory_base);
            ++r->data_patterns;
            if (got != wanted)
                return failure(r, GENISIS_POST_DATA, p->memory_base, wanted, got);
        }
    }
    observe(o, GENISIS_PHASE_DATA, 64, 64);
    /* Write ALL address probes before reading them: aliased rank/bank/row/column
     * wires then overwrite an earlier signature and cannot pass accidentally. */
    for (uint32_t offset = 4; offset <= p->memory_bytes - 4u; offset <<= 1)
    {
        if (count == 31u)
            return failure(r, GENISIS_POST_PLATFORM, 0, 31, count);
        addresses[count++] = p->memory_base + offset;
        if (offset > UINT32_MAX / 2u)
            break;
    }
    uintptr_t last = p->memory_base + p->memory_bytes - 4u;
    if (addresses[count - 1] != last)
        addresses[count++] = last;
    observe(o, GENISIS_PHASE_ADDRESS, 0, count);
    for (unsigned i = 0; i < count; ++i)
        genisis_hal_write32(addresses[i], 0x6d8e47b3u ^ (uint32_t)(addresses[i] - p->memory_base));
    for (unsigned i = 0; i < count; ++i)
    {
        uint32_t wanted = 0x6d8e47b3u ^ (uint32_t)(addresses[i] - p->memory_base);
        uint32_t got = genisis_hal_read32(addresses[i]);
        ++r->address_words;
        if (got != wanted)
            return failure(r, GENISIS_POST_ADDRESS, addresses[i], wanted, got);
    }
    observe(o, GENISIS_PHASE_ADDRESS, count, count);
    return 1;
}

/* Fill the complete span before reading to expose aliases between distant
 * words. Repeat with the inverse pattern to exercise both bit values.
 * Report progress at each completed 1 MiB boundary. */
static int memory_full(const struct genisis_platform *p, struct genisis_post_result *r,
                       const struct genisis_post_options *o)
{
    uint32_t bytes = o->full_memory_bytes;
    for (unsigned pattern = 0; pattern < 2; ++pattern)
    {
        unsigned write_phase = pattern ? GENISIS_PHASE_WRITE_INVERSE : GENISIS_PHASE_WRITE_ADDRESS;
        unsigned read_phase = pattern ? GENISIS_PHASE_READ_INVERSE : GENISIS_PHASE_READ_ADDRESS;
        observe(o, write_phase, 0, bytes);
        for (uint32_t offset = 0; offset < bytes; offset += 4)
        {
            uint32_t value = offset ^ 0x6d8e47b3u;
            if (pattern)
                value = ~value;
            genisis_hal_write32(p->memory_base + offset, value);
            uint32_t done = offset + 4u;
            if (!(done & 0xfffffu) || done == bytes)
                observe(o, write_phase, done, bytes);
        }
        observe(o, read_phase, 0, bytes);
        for (uint32_t offset = 0; offset < bytes; offset += 4)
        {
            uint32_t wanted = offset ^ 0x6d8e47b3u;
            if (pattern)
                wanted = ~wanted;
            uint32_t got = genisis_hal_read32(p->memory_base + offset);
            if (got != wanted)
                return failure(r, GENISIS_POST_MEMORY, p->memory_base + offset, wanted, got);
            uint32_t done = offset + 4u;
            if (!(done & 0xfffffu) || done == bytes)
                observe(o, read_phase, done, bytes);
        }
        ++r->full_patterns;
    }
    r->full_bytes = bytes;
    return 1;
}

int genisis_post_run_ex(const struct genisis_platform *p, struct genisis_post_result *r,
                        const struct genisis_post_options *o)
{
    r->passed = r->error = r->expected = r->actual = r->data_patterns = r->address_words = 0;
    r->address = 0;
    r->full_bytes = r->full_patterns = 0;
    const uint32_t required = GENISIS_CPU | GENISIS_UART | GENISIS_SDRAM;
    if (!p || (p->integrated & required) != required || p->memory_bytes < 8u ||
        (p->memory_base & 3u) || (p->memory_bytes & 3u) ||
        p->memory_base > UINTPTR_MAX - (p->memory_bytes - 1u) ||
        (o && o->full_memory_bytes &&
         ((o->full_memory_bytes & 3u) || o->full_memory_bytes < 8u ||
          o->full_memory_bytes > p->memory_bytes)))
        return failure(r, GENISIS_POST_PLATFORM, 0, required, p ? p->integrated : 0);
    observe(o, GENISIS_PHASE_CPU, 0, 1);
    if (!genisis_hal_check_cpu())
        return failure(r, GENISIS_POST_CPU, 0, 1, 0);
    r->passed |= GENISIS_CPU;
    observe(o, GENISIS_PHASE_CPU, 1, 1);
    observe(o, GENISIS_PHASE_UART, 0, 1);
    if (!genisis_hal_check_uart())
        return failure(r, GENISIS_POST_UART, 0, 1, 0);
    r->passed |= GENISIS_UART;
    observe(o, GENISIS_PHASE_UART, 1, 1);
    if (!memory_post(p, r, o))
        return 0;
    if (o && o->full_memory_bytes && !memory_full(p, r, o))
        return 0;
    /* Restore the historical marker only after all memory tests succeed. */
    genisis_hal_write32(p->memory_base, 0x47454e49u);
    r->passed |= GENISIS_SDRAM;
    if (p->integrated & GENISIS_TIMER)
    {
        observe(o, GENISIS_PHASE_TIMER, 0, 1);
        if (!genisis_hal_check_timer())
            return failure(r, GENISIS_POST_TIMER, 0, 1, 0);
        r->passed |= GENISIS_TIMER;
        observe(o, GENISIS_PHASE_TIMER, 1, 1);
    }
    return 1;
}

int genisis_post_run(const struct genisis_platform *p, struct genisis_post_result *r)
{
    return genisis_post_run_ex(p, r, 0);
}
