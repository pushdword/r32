/* Operator actions live outside POST. Neither network acquisition nor clock
 * setting happens on a normal boot. Hardware/protocol drivers stay reusable. */
#include "setup.h"
#include "dhcp.h"
#include "video.h"
#include "input.h"

static void decimal(uint32_t v)
{
    unsigned char digits[10];
    unsigned n = 0;
    do
    {
        digits[n++] = (unsigned char)('0' + v % 10u);
        v /= 10u;
    } while (v);
    while (n)
        genisis_hal_putc(digits[--n]);
}

static void two(unsigned v)
{
    genisis_hal_putc((unsigned char)('0' + v / 10u));
    genisis_hal_putc((unsigned char)('0' + v % 10u));
}

static int open_bus(const struct genisis_platform *p, struct genisis_pmod *bus)
{
    return p && (p->integrated & GENISIS_PMOD) && genisis_pmod_open(bus, p->pmod_base, p->clock_hz);
}

static int key(const struct genisis_platform *p)
{
    /* Read UART first. A USB key is a fresh queue event, not a repeated held
     * key or a byte allowed to enter the binary download protocol. */
    int k = genisis_input_wait(p);
    return k == GENISIS_KEY_F10 ? 27 : k;
}

static void rtc_info(const struct genisis_rtc *r)
{
    genisis_hal_puts("RTC: ");
    if (r->status != GENISIS_RTC_READY && r->status != GENISIS_RTC_UNSET)
    {
        genisis_hal_puts("NOT AVAILABLE OR INVALID CALENDAR\r\n");
        return;
    }
    decimal(r->year);
    genisis_hal_putc('-');
    two(r->month);
    genisis_hal_putc('-');
    two(r->day);
    genisis_hal_putc(' ');
    two(r->hour);
    genisis_hal_putc(':');
    two(r->minute);
    genisis_hal_putc(':');
    two(r->second);
    genisis_hal_puts(r->osf ? " UTC / TIME UNSET (OSF)\r\n" : " UTC\r\n");
}

static int edit(const struct genisis_platform *p, const char *name, unsigned previous,
                unsigned digits, unsigned *value)
{
    genisis_hal_puts(name);
    genisis_hal_puts(" [");
    decimal(previous);
    genisis_hal_puts("] : ");
    unsigned count = 0, number = 0;
    for (;;)
    {
        int k = key(p);
        if (k == 27)
        {
            genisis_hal_puts("\r\nCANCELLED\r\n");
            return 0;
        }
        if (k == '\r' || k == '\n')
        {
            *value = count ? number : previous;
            genisis_hal_puts("\r\n");
            return 1;
        }
        if ((k == 8 || k == 127) && count)
        {
            number /= 10u;
            --count;
            genisis_hal_puts("\b \b");
        }
        else if (k >= '0' && k <= '9' && count < digits)
        {
            number = number * 10u + (unsigned)(k - '0');
            ++count;
            genisis_hal_putc((unsigned char)k);
        }
    }
}

int genisis_rtc_setup(const struct genisis_platform *p, struct genisis_rtc *r)
{
    genisis_hal_puts("GENISIS BIOS SETUP - DATE AND TIME\r\n");
    struct genisis_pmod b;
    if (!open_bus(p, &b))
    {
        genisis_hal_puts("RTC CONTROLLER NOT AVAILABLE\r\n");
        return 1;
    }
    genisis_rtc_probe(&b, r);
    rtc_info(r);
    genisis_hal_puts("RTC STORES UTC / 24-HOUR CLOCK\r\n1 EDIT DATE/TIME / ESC BACK\r\n");
    if (key(p) != '1')
        return 0;
    struct genisis_rtc c;
    c.year = r->year >= 2000u && r->year <= 2199u ? r->year : 2000u;
    c.month = r->month >= 1u && r->month <= 12u ? r->month : 1u;
    c.day = r->day >= 1u && r->day <= 31u ? r->day : 1u;
    c.hour = r->hour < 24u ? r->hour : 0u;
    c.minute = r->minute < 60u ? r->minute : 0u;
    c.second = r->second < 60u ? r->second : 0u;
    genisis_hal_puts("TYPE A VALUE, ENTER TO ACCEPT / EMPTY KEEPS VALUE / ESC CANCELS\r\n");
    if (!edit(p, "YEAR", c.year, 4, &c.year) || !edit(p, "MONTH", c.month, 2, &c.month) ||
        !edit(p, "DAY", c.day, 2, &c.day) || !edit(p, "HOUR", c.hour, 2, &c.hour) ||
        !edit(p, "MINUTE", c.minute, 2, &c.minute) || !edit(p, "SECOND", c.second, 2, &c.second))
        return 0;
    genisis_hal_puts("1 SAVE TO RTC / ESC DISCARD\r\n");
    if (key(p) != '1')
    {
        genisis_hal_puts("CHANGES DISCARDED\r\n");
        return 0;
    }
    genisis_hal_puts(genisis_rtc_set(&b, &c) ? "RTC SAVED AND VERIFIED\r\n"
                                             : "INVALID DATE/TIME OR RTC WRITE/VERIFY FAILED\r\n");
    genisis_rtc_probe(&b, r);
    rtc_info(r);
    return 1;
}

void genisis_rtc_set_uart(const struct genisis_platform *p, struct genisis_rtc *r)
{
    /* Host sends fourteen ACK-paced digits. Time comes from the PC now,
     * not the compile date. Fixed bound and complete input before writes. */
    struct genisis_pmod b;
    if (!open_bus(p, &b))
    {
        genisis_hal_puts("GENISIS RTC ERROR CONTROLLER\r\n");
        return;
    }
    unsigned fields[6];
    genisis_pmod_zero(fields, (unsigned)sizeof fields);
    genisis_hal_puts("GENISIS RTC SET UTC YYYYMMDDHHMMSS\r\n");
    for (unsigned f = 0; f < 6u; ++f)
        for (unsigned i = 0; i < (f ? 2u : 4u); ++i)
        {
            genisis_hal_putc(6);
            int k = genisis_hal_get_byte(1);
            if (k < '0' || k > '9')
            {
                genisis_hal_puts("GENISIS RTC ERROR INPUT\r\n");
                return;
            }
            fields[f] = fields[f] * 10u + (unsigned)(k - '0');
        }
    struct genisis_rtc date;
    date.year = fields[0];
    date.month = fields[1];
    date.day = fields[2];
    date.hour = fields[3];
    date.minute = fields[4];
    date.second = fields[5];
    genisis_hal_puts(genisis_rtc_set(&b, &date) ? "GENISIS RTC SET OK\r\n"
                                                : "GENISIS RTC ERROR WRITE/VERIFY\r\n");
    genisis_rtc_probe(&b, r);
    rtc_info(r);
}

struct context
{
    struct genisis_pmod bus;
    uint32_t last, ms, remainder;
};

static int net_send(void *ctx, const unsigned char *ip, unsigned port, const unsigned char *data,
                    unsigned size)
{
    struct context *c = ctx;
    return genisis_w5500_udp_send(&c->bus, ip, port, data, size);
}

static int net_receive(void *ctx, unsigned char *ip, unsigned *port, unsigned char *data,
                       unsigned size)
{
    struct context *c = ctx;
    return genisis_w5500_udp_receive(&c->bus, ip, port, data, size);
}

static uint32_t milliseconds(void *ctx)
{
    struct context *c = ctx;
    uint32_t now = genisis_hal_read32(c->bus.base + 36u);
    uint32_t cycles = now - c->last + c->remainder, per_ms = c->bus.hz / 1000u;
    c->last = now;
    c->ms += cycles / per_ms;
    c->remainder = cycles % per_ms;
    return c->ms;
}

static int idle(void *ctx)
{
    struct context *c = ctx;
    return genisis_pmod_delay(&c->bus, 10000);
}

static void event(void *ctx, unsigned e)
{
    (void)ctx;
    static const char *const names[] = {"", "DISCOVER", "OFFER", "REQUEST", "ACK"};
    if (e < 5u)
    {
        genisis_hal_puts("DHCP TEST: ");
        genisis_hal_puts(names[e]);
        genisis_hal_puts("\r\n");
    }
}

static void ipv4(const char *label, const unsigned char *ip)
{
    genisis_hal_puts(label);
    for (unsigned i = 0; i < 4u; ++i)
    {
        if (i)
            genisis_hal_putc('.');
        decimal(ip[i]);
    }
    genisis_hal_puts("\r\n");
}

void genisis_network_test(const struct genisis_platform *p, struct genisis_w5500 *nic)
{
    genisis_hal_puts("GENISIS BIOS SETUP - NETWORK TEST\r\nDHCP DIAGNOSTIC / NOT RUN AT BOOT\r\n");
    struct context c;
    if (!open_bus(p, &c.bus) || nic->status != GENISIS_W5500_READY)
    {
        genisis_hal_puts("W5500 NOT AVAILABLE\r\n");
        return;
    }
    if (!genisis_w5500_link(&c.bus, nic, 3000) || !nic->link)
    {
        genisis_hal_puts("NO ETHERNET LINK\r\n");
        return;
    }
    /* Locally administered unicast MAC for the firmware network test. */
    static const unsigned char mac[6] = {2, 0x58, 0x32, 0x25, 3, 0x17};
    genisis_hal_puts("MAC: 02:58:32:25:03:17\r\n");
    if (!genisis_w5500_udp_open(&c.bus, mac, 68))
    {
        (void)genisis_w5500_udp_close(&c.bus);
        genisis_hal_puts("DHCP TEST ERROR: UDP OPEN\r\n");
        return;
    }
    c.last = genisis_hal_read32(c.bus.base + 36u);
    c.ms = 0;
    c.remainder = 0;
    struct genisis_dhcp_io io = {&c, net_send, net_receive, milliseconds, idle, event};
    struct genisis_dhcp_lease lease;
    uint32_t xid = c.last ^ 0x58322517u;
    if (!xid)
        xid = 1;
    genisis_dhcp_acquire(&io, mac, xid, &lease);
    if (lease.status == GENISIS_DHCP_BOUND)
    {
        genisis_hal_puts("DHCP TEST OK\r\n");
        ipv4("IP: ", lease.ip);
        ipv4("MASK: ", lease.mask);
        ipv4("GATEWAY: ", lease.gateway);
        ipv4("DNS: ", lease.dns);
        ipv4("SERVER: ", lease.server);
        genisis_hal_puts("LEASE SECONDS: ");
        decimal(lease.seconds);
        genisis_hal_puts("\r\n");
        int configured = genisis_w5500_config(&c.bus, lease.ip, lease.mask, lease.gateway);
        int released = configured && genisis_dhcp_release(&io, mac, &lease);
        genisis_hal_puts(released ? "DHCP RELEASE SENT\r\n"
                                  : "DHCP RELEASE NOT SENT / LEASE WILL EXPIRE\r\n");
    }
    else
    {
        genisis_hal_puts("DHCP TEST FAILED: ");
        genisis_hal_puts(lease.status == GENISIS_DHCP_TIMEOUT ? "NO SERVER RESPONSE"
                         : lease.status == GENISIS_DHCP_NAK   ? "SERVER NAK"
                                                              : "TRANSPORT/TIMER ERROR");
        genisis_hal_puts("\r\n");
    }
    genisis_hal_puts(genisis_w5500_udp_close(&c.bus)
                         ? "NETWORK TEST FINISHED / TEMPORARY CONFIG CLEARED\r\n"
                         : "NETWORK CLEANUP FAILED\r\n");
}
