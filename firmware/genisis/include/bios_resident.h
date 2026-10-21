/* Internal Genisis split-image interface. Boot_info/ISA/C ABI stay unchanged. */
#ifndef GENISIS_BIOS_RESIDENT_H
#define GENISIS_BIOS_RESIDENT_H
#include <stdint.h>
#include "post.h"
void genisis_bios_progress(unsigned phase, uint32_t done, uint32_t total);
void genisis_bios_stage0(void);
void genisis_bios_reload(void);
int genisis_bios_memory_test(const struct genisis_platform *platform,
                             struct genisis_post_result *result, uint32_t bytes);
#endif
