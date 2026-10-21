/* Destructive power-on diagnostics before image loading.
 * Quick POST probes data/address lines. Extended POST sweeps the RAM range. */
#ifndef GENISIS_POST_H
#define GENISIS_POST_H
#include "hal.h"

enum genisis_post_error
{
    GENISIS_POST_OK = 0,
    GENISIS_POST_PLATFORM = 1,
    GENISIS_POST_CPU = 2,
    GENISIS_POST_UART = 3,
    GENISIS_POST_DATA = 4,
    GENISIS_POST_ADDRESS = 5,
    GENISIS_POST_TIMER = 6,
    GENISIS_POST_MEMORY = 7
};

struct genisis_post_result
{
    uint32_t passed, error;
    uintptr_t address;
    uint32_t expected, actual, data_patterns, address_words;
    uint32_t full_bytes, full_patterns;
};

enum genisis_post_phase
{
    GENISIS_PHASE_CPU,
    GENISIS_PHASE_UART,
    GENISIS_PHASE_DATA,
    GENISIS_PHASE_ADDRESS,
    GENISIS_PHASE_WRITE_ADDRESS,
    GENISIS_PHASE_READ_ADDRESS,
    GENISIS_PHASE_WRITE_INVERSE,
    GENISIS_PHASE_READ_INVERSE,
    GENISIS_PHASE_TIMER
};

typedef void (*genisis_post_observer)(unsigned phase, uint32_t done, uint32_t total);

struct genisis_post_options
{
    /* Zero selects quick POST. Nonzero spans are filled and read back with
     * an address-derived pattern and its inverse. Report the tested span
     * when simulation uses a reduced range. */
    uint32_t full_memory_bytes;
    genisis_post_observer observe;
};

int genisis_post_run(const struct genisis_platform *platform, struct genisis_post_result *result);
int genisis_post_run_ex(const struct genisis_platform *platform, struct genisis_post_result *result,
                        const struct genisis_post_options *options);
#endif
