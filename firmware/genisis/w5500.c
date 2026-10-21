#include "w5500.h"
#include "hal.h"

enum
{
    COMMON = 0,
    SOCKET0 = 1,
    TX0 = 2,
    RX0 = 3
};

static int transfer(struct genisis_pmod *b, unsigned byte)
{
    genisis_hal_write32(b->base + 8u, byte);
    unsigned budget = 20000u;
    while (genisis_hal_read32(b->base + 12u) & 1u)
        if (!--budget)
            return -1;
    return (int)(genisis_hal_read32(b->base + 8u) & 255u);
}

static int access(struct genisis_pmod *b, unsigned block, unsigned address, unsigned char *out,
                  const unsigned char *in, unsigned size)
{
    if (block > 31u || address > 65535u || !size || size > 2048u)
        return 0;
    genisis_hal_write32(b->base + 4u, 0);
    /* Hold CS for the complete VDM block/RWB transfer. The chip wraps its
     * 16-bit offset and maps TX/RX pointers into the allocated buffer. */
    int ok = transfer(b, address >> 8) >= 0 && transfer(b, address & 255u) >= 0 &&
             transfer(b, (block << 3) | (in ? 4u : 0u)) >= 0;
    for (unsigned i = 0; ok && i < size; ++i)
    {
        int v = transfer(b, in ? in[i] : 255u);
        if (v < 0)
        {
            ok = 0;
            break;
        }
        if (out)
            out[i] = (unsigned char)v;
    }
    if (!ok)
        genisis_hal_write32(b->base + 20u, 1);
    else
        genisis_hal_write32(b->base + 4u, 1);
    return ok;
}

int genisis_w5500_read(struct genisis_pmod *b, unsigned block, unsigned address,
                       unsigned char *data, unsigned size)
{
    return data && access(b, block, address, data, 0, size);
}

int genisis_w5500_write(struct genisis_pmod *b, unsigned block, unsigned address,
                        const unsigned char *data, unsigned size)
{
    return data && access(b, block, address, 0, data, size);
}

static int read_reg(struct genisis_pmod *b, unsigned address)
{
    unsigned char byte;
    return genisis_w5500_read(b, COMMON, address, &byte, 1) ? byte : -1;
}

static int write_byte(struct genisis_pmod *b, unsigned block, unsigned address, unsigned byte)
{
    unsigned char v = (unsigned char)byte;
    return genisis_w5500_write(b, block, address, &v, 1);
}

static int read_word(struct genisis_pmod *b, unsigned address)
{
    unsigned char v[2];
    return genisis_w5500_read(b, SOCKET0, address, v, 2) ? (int)((unsigned)v[0] * 256u + v[1]) : -1;
}

static int stable_word(struct genisis_pmod *b, unsigned address)
{
    int first = read_word(b, address);
    if (first < 0)
        return -1;
    for (unsigned i = 0; i < 8u; ++i)
    {
        int next = read_word(b, address);
        if (next < 0)
            return -1;
        if (next == first)
            return first;
        first = next;
    }
    return -1;
}

static int write_word(struct genisis_pmod *b, unsigned address, unsigned value)
{
    unsigned char v[2] = {(unsigned char)(value >> 8), (unsigned char)value};
    return genisis_w5500_write(b, SOCKET0, address, v, 2);
}

static int command(struct genisis_pmod *b, unsigned cmd)
{
    unsigned char value;
    if (!write_byte(b, SOCKET0, 1, cmd))
        return 0;
    for (unsigned i = 0; i < 100u; ++i)
    {
        if (!genisis_w5500_read(b, SOCKET0, 1, &value, 1))
            return 0;
        if (!value)
            return 1;
        if (!genisis_pmod_delay(b, 1000))
            return 0;
    }
    return 0;
}

void genisis_w5500_probe(struct genisis_pmod *b, struct genisis_w5500 *n)
{
    genisis_pmod_zero(n, (unsigned)sizeof *n);
    n->status = GENISIS_W5500_TIMEOUT;
    genisis_hal_write32(b->base + 20u, 1);
    /* Hardware reset >=500us, and >1ms for the internal PLL after release. */
    b->control &= ~1u;
    genisis_hal_write32(b->base + 24u, b->control);
    if (!genisis_pmod_delay(b, 2000))
        return;
    b->control |= 1u;
    genisis_hal_write32(b->base + 24u, b->control);
    if (!genisis_pmod_delay(b, 2000))
        return;
    uint32_t divider = (b->hz + 1999999u) / 2000000u; /* At most 1MHz for initial wiring. */
    genisis_hal_write32(b->base, divider);
    n->status = GENISIS_W5500_TRANSPORT;
    int version = read_reg(b, 0x39);
    if (version < 0)
        return;
    n->version = (unsigned)version;
    if (version == 0 || version == 255)
    {
        n->status = GENISIS_W5500_ABSENT;
        return;
    }
    n->status = GENISIS_W5500_VERSION;
    if (version != 4 || read_reg(b, 0x39) != version)
        return;
    int phy = read_reg(b, 0x2e);
    if (phy < 0)
    {
        n->status = GENISIS_W5500_TRANSPORT;
        return;
    }
    n->phy = (unsigned)phy;
    n->link = n->phy & 1u;
    n->speed100 = (n->phy >> 1) & 1u;
    n->full_duplex = (n->phy >> 2) & 1u;
    n->interrupt = !(genisis_hal_read32(b->base + 28u) & 4u);
    n->status = GENISIS_W5500_READY;
}

int genisis_w5500_link(struct genisis_pmod *b, struct genisis_w5500 *n, unsigned timeout_ms)
{
    if (n->status != GENISIS_W5500_READY || timeout_ms > 5000u)
        return 0;
    for (unsigned elapsed = 0;; elapsed += 10u)
    {
        int phy = read_reg(b, 0x2e);
        if (phy < 0)
            return 0;
        n->phy = (unsigned)phy;
        n->link = n->phy & 1u;
        n->speed100 = (n->phy >> 1) & 1u;
        n->full_duplex = (n->phy >> 2) & 1u;
        n->interrupt = !(genisis_hal_read32(b->base + 28u) & 4u);
        if (n->link || elapsed >= timeout_ms)
            return 1;
        if (!genisis_pmod_delay(b, 10000))
            return 0;
    }
}

int genisis_w5500_config(struct genisis_pmod *b, const unsigned char ip[4],
                         const unsigned char mask[4], const unsigned char gateway[4])
{
    if (!genisis_w5500_write(b, COMMON, 1, gateway, 4) ||
        !genisis_w5500_write(b, COMMON, 5, mask, 4) || !genisis_w5500_write(b, COMMON, 15, ip, 4))
        return 0;
    unsigned char actual[4];
    for (unsigned group = 0; group < 3u; ++group)
    {
        const unsigned char *wanted = group == 0 ? gateway : group == 1 ? mask : ip;
        if (!genisis_w5500_read(b, COMMON, group == 0 ? 1u : group == 1 ? 5u : 15u, actual, 4))
            return 0;
        for (unsigned i = 0; i < 4u; ++i)
            if (actual[i] != wanted[i])
                return 0;
    }
    return 1;
}

int genisis_w5500_udp_close(struct genisis_pmod *b)
{
    const unsigned char zero[4] = {0, 0, 0, 0};
    int ok = command(b, 0x10);
    if (!genisis_w5500_config(b, zero, zero, zero))
        ok = 0;
    genisis_hal_write32(b->base + 4u, 1);
    return ok;
}

int genisis_w5500_udp_open(struct genisis_pmod *b, const unsigned char mac[6], unsigned port)
{
    if (!port || port > 65535u || !genisis_w5500_udp_close(b))
        return 0;
    unsigned char size;
    if (!genisis_w5500_read(b, SOCKET0, 0x1e, &size, 1) || size != 2u ||
        !genisis_w5500_read(b, SOCKET0, 0x1f, &size, 1) || size != 2u)
        return 0;
    if (!genisis_w5500_write(b, COMMON, 9, mac, 6) || !write_byte(b, SOCKET0, 0, 2) ||
        !write_word(b, 4, port) || !write_byte(b, SOCKET0, 2, 0xff) || !command(b, 1))
        return 0;
    unsigned char status;
    return genisis_w5500_read(b, SOCKET0, 3, &status, 1) && status == 0x22u;
}

int genisis_w5500_udp_send(struct genisis_pmod *b, const unsigned char ip[4], unsigned port,
                           const unsigned char *data, unsigned size)
{
    if (!port || port > 65535u || !data || !size || size > 2048u)
        return 0;
    int free = stable_word(b, 0x20), pointer = read_word(b, 0x24);
    if (free < 0 || pointer < 0 || (unsigned)free < size)
        return 0;
    int broadcast = ip[0] == 255u && ip[1] == 255u && ip[2] == 255u && ip[3] == 255u;
    const unsigned char dest_mac[6] = {255, 255, 255, 255, 255, 255};
    if (!genisis_w5500_write(b, SOCKET0, 12, ip, 4) || !write_word(b, 16, port) ||
        (broadcast && !genisis_w5500_write(b, SOCKET0, 6, dest_mac, 6)) ||
        !write_byte(b, SOCKET0, 2, 0x18) ||
        !genisis_w5500_write(b, TX0, (unsigned)pointer, data, size) ||
        !write_word(b, 0x24, ((unsigned)pointer + size) & 65535u) ||
        !command(b, broadcast ? 0x21u : 0x20u))
        return 0;
    for (unsigned i = 0; i < 3000u; ++i)
    {
        unsigned char ir;
        if (!genisis_w5500_read(b, SOCKET0, 2, &ir, 1))
            return 0;
        if (ir & 0x18u)
        {
            (void)write_byte(b, SOCKET0, 2, ir & 0x18u);
            return (ir & 0x18u) == 0x10u;
        }
        if (!genisis_pmod_delay(b, 1000))
            return 0;
    }
    return 0;
}

int genisis_w5500_udp_receive(struct genisis_pmod *b, unsigned char ip[4], unsigned *port,
                              unsigned char *data, unsigned capacity)
{
    int available = stable_word(b, 0x26), pointer = read_word(b, 0x28);
    if (available < 0 || pointer < 0 || available > 2048)
        return -1;
    if (available < 8)
        return 0;
    unsigned char header[8];
    if (!genisis_w5500_read(b, RX0, (unsigned)pointer, header, 8))
        return -1;
    unsigned size = (unsigned)header[6] * 256u + header[7];
    if (size > 2040u)
        return -1;
    if ((unsigned)available < size + 8u)
        return 0;
    unsigned next = ((unsigned)pointer + 8u + size) & 65535u;
    int keep = size <= capacity;
    if (keep && size && !genisis_w5500_read(b, RX0, ((unsigned)pointer + 8u) & 65535u, data, size))
        return -1;
    if (!write_word(b, 0x28, next) || !command(b, 0x40))
        return -1;
    if (!keep)
        return 0; /* Consume the whole oversize datagram, preserve following packets. */
    for (unsigned i = 0; i < 4u; ++i)
        ip[i] = header[i];
    *port = (unsigned)header[4] * 256u + header[5];
    return (int)size;
}
