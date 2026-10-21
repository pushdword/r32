/* BIOS setup actions for manual network diagnostics and clock updates.
 * Clock changes use edit/save or the ACK-paced host clock command. */
#ifndef GENISIS_SETUP_H
#define GENISIS_SETUP_H
#include "hal.h"
#include "rtc.h"
#include "w5500.h"
int genisis_rtc_setup(const struct genisis_platform *platform, struct genisis_rtc *rtc);
void genisis_rtc_set_uart(const struct genisis_platform *platform, struct genisis_rtc *rtc);
void genisis_network_test(const struct genisis_platform *platform, struct genisis_w5500 *nic);
#endif
