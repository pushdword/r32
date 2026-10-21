#ifndef GENISIS_RTC_H
#define GENISIS_RTC_H
#include "pmod.h"

enum genisis_rtc_status
{
    GENISIS_RTC_ABSENT = 0,
    GENISIS_RTC_READY = 1,
    GENISIS_RTC_UNSET = 2,
    GENISIS_RTC_INVALID = 3,
    GENISIS_RTC_BUS = 4,
    GENISIS_RTC_TIMEOUT = 5
};

struct genisis_rtc
{
    uint32_t status, responded, year, month, day, hour, minute, second, osf;
};

/* ACK at 0x68 plus a plausible register map means DS3231-compatible,
 * not a unique silicon ID. No date/alarm/flag or battery settings are written. */
void genisis_rtc_probe(struct genisis_pmod *bus, struct genisis_rtc *rtc);
/* Explicit setup action only. UTC Gregorian calendar, 2000..2199, 24h.
 * Starts battery-backed oscillator, clears OSF after successful calendar
 * write and verifies a fresh read. POST never calls this automatically. */
int genisis_rtc_set(struct genisis_pmod *bus, const struct genisis_rtc *utc);
#endif
