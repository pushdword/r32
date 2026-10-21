/* Single-master software I2C with open-drain pads.
 * Bound waits for clock stretching, ACK/NACK and STOP. End reads with NACK.
 * Recovery pulses require SCL high and end with STOP before probing. */
#include "rtc.h"
#include "hal.h"

static int pause_bus(struct genisis_pmod *b)
{
    return genisis_pmod_delay(b, 5);
}

static unsigned lines(struct genisis_pmod *b)
{
    return genisis_hal_read32(b->base + 28u) & 3u;
}

static int high(struct genisis_pmod *b, unsigned sda_low)
{
    genisis_pmod_control(b, 0, sda_low);
    uint32_t first = genisis_hal_read32(b->base + 36u);
    unsigned budget = 10000u;
    while (!(lines(b) & 1u))
        if (!--budget || genisis_hal_read32(b->base + 36u) - first >= b->hz / 1000u)
            return 0;
    return pause_bus(b);
}

static int stop(struct genisis_pmod *b)
{
    genisis_pmod_control(b, 1, 1);
    int ok = pause_bus(b) && high(b, 1);
    genisis_pmod_release(b);
    return pause_bus(b) && ok;
}

static int start(struct genisis_pmod *b)
{
    genisis_pmod_control(b, 1, 0);
    if (!pause_bus(b))
        return 0;
    if (!high(b, 0) || (lines(b) & 3u) != 3u)
        return 0;
    genisis_pmod_control(b, 0, 1);
    if (!pause_bus(b))
        return 0;
    genisis_pmod_control(b, 1, 1);
    return pause_bus(b);
}

static int send(struct genisis_pmod *b, unsigned byte)
{
    for (unsigned mask = 128; mask; mask >>= 1)
    {
        unsigned low = !(byte & mask);
        genisis_pmod_control(b, 1, low);
        if (!pause_bus(b) || !high(b, low))
            return -1;
        genisis_pmod_control(b, 1, low);
    }
    genisis_pmod_control(b, 1, 0);
    if (!pause_bus(b) || !high(b, 0))
        return -1;
    unsigned ack = !(lines(b) & 2u);
    genisis_pmod_control(b, 1, 0);
    return (int)ack;
}

static int receive(struct genisis_pmod *b, unsigned final)
{
    unsigned byte = 0;
    for (unsigned bit = 0; bit < 8; ++bit)
    {
        genisis_pmod_control(b, 1, 0);
        if (!pause_bus(b) || !high(b, 0))
            return -1;
        byte = (byte << 1) | ((lines(b) >> 1) & 1u);
        genisis_pmod_control(b, 1, 0);
    }
    genisis_pmod_control(b, 1, !final);
    if (!pause_bus(b) || !high(b, !final))
        return -1;
    genisis_pmod_control(b, 1, 0);
    return (int)byte;
}

static int read_regs(struct genisis_pmod *b, unsigned offset, unsigned char *bytes, unsigned count)
{
    int result = -1, ack;
    if (!start(b))
        goto done;
    ack = send(b, 0xd0);
    if (ack != 1)
    {
        result = ack;
        goto done;
    }
    if (send(b, offset) != 1 || !start(b) || send(b, 0xd1) != 1)
        goto done;
    for (unsigned i = 0; i < count; ++i)
    {
        int value = receive(b, i + 1 == count);
        if (value < 0)
            goto done;
        bytes[i] = (unsigned char)value;
    }
    result = 1;
done:
    if (!stop(b))
        result = -1;
    return result;
}

static int bcd(unsigned byte, unsigned *value)
{
    if ((byte & 15u) > 9u || (byte >> 4) > 9u)
        return 0;
    *value = (byte >> 4) * 10u + (byte & 15u);
    return 1;
}

static int valid_date(const struct genisis_rtc *r)
{
    static const unsigned char days[12] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    if (r->year < 2000u || r->year > 2199u || r->month < 1u || r->month > 12u || r->day < 1u ||
        r->hour > 23u || r->minute > 59u || r->second > 59u)
        return 0;
    unsigned limit = days[r->month - 1u];
    if (r->month == 2u && r->year % 4u == 0u && (r->year % 100u != 0u || r->year % 400u == 0u))
        ++limit;
    return r->day <= limit;
}

static unsigned char encode(unsigned value)
{
    return (unsigned char)((value / 10u) * 16u + value % 10u);
}

static int write_regs(struct genisis_pmod *b, unsigned offset, const unsigned char *bytes,
                      unsigned count)
{
    int ok = 0;
    if (!start(b) || send(b, 0xd0) != 1 || send(b, offset) != 1)
        goto done;
    for (unsigned i = 0; i < count; ++i)
        if (send(b, bytes[i]) != 1)
            goto done;
    ok = 1;
done:
    if (!stop(b))
        ok = 0;
    return ok;
}

int genisis_rtc_set(struct genisis_pmod *b, const struct genisis_rtc *r)
{
    if (!valid_date(r))
        return 0; /* Reject every bad field before a write. */
    unsigned y = r->year, m = r->month;
    static const unsigned char offsets[12] = {0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4};
    if (m < 3u)
        --y;
    unsigned weekday = (y + y / 4u - y / 100u + y / 400u + offsets[m - 1u] + r->day) % 7u + 1u;
    unsigned char data[7] = {
        encode(r->second),     encode(r->minute),
        encode(r->hour),       (unsigned char)weekday,
        encode(r->day),        (unsigned char)(encode(r->month) | (r->year >= 2100u ? 128u : 0u)),
        encode(r->year % 100u)};
    unsigned char control, status;
    if (read_regs(b, 14, &control, 1) != 1 || read_regs(b, 15, &status, 1) != 1)
        return 0;
    control &= 127u; /* EOSC=0 permits the oscillator to run on the battery. */
    if (!write_regs(b, 14, &control, 1) || !write_regs(b, 0, data, 7))
        return 0;
    /* Write ones to preserve alarm flags asserted after the status read.
     * Retain EN32kHz and clear OSF. Alarm flags clear on a zero write. */
    status = (unsigned char)((status & 8u) | 3u);
    if (!write_regs(b, 15, &status, 1))
        return 0;
    struct genisis_rtc actual;
    genisis_rtc_probe(b, &actual);
    /* Setting/readback is normally <1s. Accept a second tick, including a
     * minute/day rollover, by checking the fields with an advanced copy. */
    if (actual.status != GENISIS_RTC_READY)
        return 0;
    struct genisis_rtc next;
    next.year = r->year;
    next.month = r->month;
    next.day = r->day;
    next.hour = r->hour;
    next.minute = r->minute;
    next.second = r->second;
    for (unsigned tick = 0; tick < 3u; ++tick)
    {
        if (actual.year == next.year && actual.month == next.month && actual.day == next.day &&
            actual.hour == next.hour && actual.minute == next.minute &&
            actual.second == next.second)
            return 1;
        if (++next.second == 60u)
        {
            next.second = 0;
            if (++next.minute == 60u)
            {
                next.minute = 0;
                if (++next.hour == 24u)
                {
                    next.hour = 0;
                    ++next.day;
                    if (!valid_date(&next))
                    {
                        next.day = 1;
                        if (++next.month == 13u)
                        {
                            next.month = 1;
                            ++next.year;
                        }
                    }
                }
            }
        }
    }
    return 0;
}

void genisis_rtc_probe(struct genisis_pmod *b, struct genisis_rtc *r)
{
    genisis_pmod_zero(r, (unsigned)sizeof *r);
    r->status = GENISIS_RTC_BUS;
    if (!high(b, 0))
        goto done;
    if (!(lines(b) & 2u))
    {
        for (unsigned i = 0; i < 9 && !(lines(b) & 2u); ++i)
        {
            genisis_pmod_control(b, 1, 0);
            if (!pause_bus(b) || !high(b, 0))
                goto done;
        }
        if (!stop(b) || (lines(b) & 3u) != 3u)
            goto done;
    }
    unsigned char data[7], status;
    int reply = read_regs(b, 0, data, 7);
    if (!reply)
    {
        r->status = GENISIS_RTC_ABSENT;
        goto done;
    }
    if (reply < 0)
        goto done;
    r->responded = 1;
    if (read_regs(b, 15, &status, 1) != 1)
        goto done;
    r->osf = (status >> 7) & 1u;
    r->status = GENISIS_RTC_INVALID;
    unsigned hour = data[2] & ((data[2] & 64u) ? 31u : 63u), year;
    if ((data[0] & 128u) || (data[1] & 128u) || (data[2] & 128u) || (data[3] & 248u) ||
        (data[4] & 192u) || (data[5] & 96u) || data[3] < 1u || data[3] > 7u ||
        !bcd(data[0], &r->second) || r->second > 59u || !bcd(data[1], &r->minute) ||
        r->minute > 59u || !bcd(hour, &r->hour) || !bcd(data[4], &r->day) ||
        !bcd(data[5] & 31u, &r->month) || !bcd(data[6], &year) || r->month < 1u || r->month > 12u ||
        r->day < 1u)
        goto done;
    if (data[2] & 64u)
    {
        if (r->hour < 1u || r->hour > 12u)
            goto done;
        r->hour = (r->hour % 12u) + ((data[2] & 32u) ? 12u : 0u);
    }
    else if (r->hour > 23u)
        goto done;
    r->year = 2000u + year + ((data[5] & 128u) ? 100u : 0u);
    static const unsigned char days[12] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    unsigned limit = days[r->month - 1u];
    if (r->month == 2u && r->year % 4u == 0u && (r->year % 100u != 0u || r->year % 400u == 0u))
        ++limit;
    if (r->day > limit)
        goto done;
    r->status = r->osf ? GENISIS_RTC_UNSET : GENISIS_RTC_READY;
done:
    genisis_pmod_release(b);
}
