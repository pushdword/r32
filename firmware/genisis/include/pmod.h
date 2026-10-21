/* Internal transport for the shared middle PMOD. Not a kernel device ABI. */
#ifndef GENISIS_PMOD_H
#define GENISIS_PMOD_H
#include <stdint.h>
#define GENISIS_PMOD_ID 0x31444d50u

struct genisis_pmod
{
    uintptr_t base;
    uint32_t hz, control;
};

int genisis_pmod_open(struct genisis_pmod *bus, uintptr_t base, uint32_t hz);
int genisis_pmod_delay(struct genisis_pmod *bus, unsigned microseconds);
void genisis_pmod_control(struct genisis_pmod *bus, unsigned scl_low, unsigned sda_low);
void genisis_pmod_release(struct genisis_pmod *bus);
void genisis_pmod_zero(void *object, unsigned bytes);
#endif
