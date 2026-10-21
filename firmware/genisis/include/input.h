/* UI keys only. The binary loader continues reading the raw UART directly. */
#ifndef GENISIS_INPUT_H
#define GENISIS_INPUT_H
#include "hal.h"

enum
{
    GENISIS_KEY_UP = 256,
    GENISIS_KEY_DOWN,
    GENISIS_KEY_LEFT,
    GENISIS_KEY_RIGHT,
    GENISIS_KEY_F1,
    GENISIS_KEY_F5,
    GENISIS_KEY_F10
};

int genisis_input_poll(const struct genisis_platform *platform);
int genisis_input_wait(const struct genisis_platform *platform);
#endif
