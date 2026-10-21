/* DHCPv4 BOOTP framing and options, RFC2131/2132. Receive packets are untrusted:
 * bounds, cookie, op/type/length, XID, chaddr, server and ACK address are checked.
 * DISCOVER/OFFER/REQUEST/ACK is an operator-triggered test, not an OS client. */
#include "dhcp.h"
static const unsigned char broadcast[4] = {255, 255, 255, 255};

static void zero(void *object, unsigned bytes)
{
    volatile unsigned char *p = object;
    while (bytes--)
        *p++ = 0;
}

static void copy(unsigned char *to, const unsigned char *from, unsigned size)
{
    volatile unsigned char *out = to;
    while (size--)
        *out++ = *from++;
}

static int equal(const unsigned char *a, const unsigned char *b, unsigned size)
{
    while (size--)
        if (*a++ != *b++)
            return 0;
    return 1;
}

static uint32_t get32(const unsigned char *p)
{
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
}

static void put32(unsigned char *p, uint32_t v)
{
    p[0] = (unsigned char)(v >> 24);
    p[1] = (unsigned char)(v >> 16);
    p[2] = (unsigned char)(v >> 8);
    p[3] = (unsigned char)v;
}

static int unicast(const unsigned char ip[4])
{
    return ip[0] != 0 && ip[0] != 127 && ip[0] < 224;
}

static int netmask(const unsigned char mask[4])
{
    uint32_t inverse = ~get32(mask);
    return (inverse & (inverse + 1u)) == 0;
}

enum
{
    TYPE = 1,
    SERVER = 2,
    MASK = 4,
    ROUTER = 8,
    DNS = 16,
    LEASE = 32,
    OVERLOAD = 64
};

struct options
{
    unsigned seen, type, overload;
    struct genisis_dhcp_lease values;
};

static int parse_options(const unsigned char *data, unsigned size, struct options *o, int primary)
{
    unsigned i = 0;
    while (i < size)
    {
        unsigned code = data[i++];
        if (code == 255u)
            return 1;
        if (!code)
            continue;
        if (i == size)
            return 0;
        unsigned n = data[i++];
        if (n > size - i)
            return 0;
        const unsigned char *v = data + i;
        unsigned flag = 0;
        switch (code)
        {
        case 53:
            if (n != 1u || v[0] < 1u || v[0] > 8u)
                return 0;
            flag = TYPE;
            if ((o->seen & flag) && o->type != v[0])
                return 0;
            o->type = v[0];
            break;
        case 54:
            if (n != 4u || !unicast(v))
                return 0;
            flag = SERVER;
            if ((o->seen & flag) && !equal(o->values.server, v, 4))
                return 0;
            copy(o->values.server, v, 4);
            break;
        case 1:
            if (n != 4u || !netmask(v))
                return 0;
            flag = MASK;
            if ((o->seen & flag) && !equal(o->values.mask, v, 4))
                return 0;
            copy(o->values.mask, v, 4);
            break;
        case 3:
            if (n < 4u || n % 4u || !unicast(v))
                return 0;
            flag = ROUTER;
            copy(o->values.gateway, v, 4);
            break;
        case 6:
            if (n < 4u || n % 4u || !unicast(v))
                return 0;
            flag = DNS;
            copy(o->values.dns, v, 4);
            break;
        case 51:
            if (n != 4u || !get32(v))
                return 0;
            flag = LEASE;
            o->values.seconds = get32(v);
            break;
        case 52:
            if (!primary || n != 1u || !v[0] || v[0] > 3u || (o->seen & OVERLOAD))
                return 0;
            flag = OVERLOAD;
            o->overload = v[0];
            break;
        default:
            break; /* Unrequested vendor options cannot escape their TLV. */
        }
        o->seen |= flag;
        i += n;
    }
    return 0; /* Each options area requires END. */
}

static int reply(const unsigned char *packet, unsigned size, const unsigned char mac[6],
                 uint32_t xid, struct options *o)
{
    if (size < 241u || size > GENISIS_DHCP_PACKET || packet[0] != 2 || packet[1] != 1 ||
        packet[2] != 6 || get32(packet + 4) != xid || !equal(packet + 28, mac, 6) ||
        get32(packet + 236) != 0x63825363u)
        return 0;
    zero(o, (unsigned)sizeof *o);
    copy(o->values.ip, packet + 16, 4);
    if (!parse_options(packet + 240, size - 240u, o, 1) ||
        ((o->overload & 1u) && !parse_options(packet + 108, 128, o, 0)) ||
        ((o->overload & 2u) && !parse_options(packet + 44, 64, o, 0)))
        return 0;
    if ((o->seen & (TYPE | SERVER)) != (TYPE | SERVER))
        return 0;
    return o->type == 6u || unicast(o->values.ip); /* NAK has yiaddr=0. */
}

static unsigned option(unsigned char *p, unsigned pos, unsigned code, const unsigned char *v,
                       unsigned size)
{
    p[pos++] = (unsigned char)code;
    p[pos++] = (unsigned char)size;
    copy(p + pos, v, size);
    return pos + size;
}

static unsigned request(unsigned char *p, unsigned type, const unsigned char mac[6], uint32_t xid,
                        const struct genisis_dhcp_lease *l, unsigned seconds)
{
    zero(p, GENISIS_DHCP_PACKET);
    p[0] = 1;
    p[1] = 1;
    p[2] = 6;
    put32(p + 4, xid);
    p[8] = (unsigned char)(seconds >> 8);
    p[9] = (unsigned char)seconds;
    if (type == 7u)
        copy(p + 12, l->ip, 4);
    else
        p[10] = 128; /* Broadcast until configured. */
    copy(p + 28, mac, 6);
    put32(p + 236, 0x63825363u);
    unsigned char mt = (unsigned char)type, client[7];
    client[0] = 1;
    copy(client + 1, mac, 6);
    unsigned n = option(p, 240, 53, &mt, 1);
    n = option(p, n, 61, client, 7);
    if (type == 3u)
        n = option(p, n, 50, l->ip, 4);
    if (type == 3u || type == 7u)
        n = option(p, n, 54, l->server, 4);
    if (type != 7u)
    {
        const unsigned char wanted[6] = {1, 3, 6, 51, 58, 59}, maximum[2] = {2, 64};
        n = option(p, n, 55, wanted, 6);
        n = option(p, n, 57, maximum, 2);
    }
    p[n++] = 255;
    return n < 300u ? 300u : n;
}

static void notify(const struct genisis_dhcp_io *io, unsigned event)
{
    if (io->event)
        io->event(io->context, event);
}

static void merge(struct genisis_dhcp_lease *to, const struct options *o)
{
    copy(to->ip, o->values.ip, 4);
    copy(to->server, o->values.server, 4);
    if (o->seen & MASK)
        copy(to->mask, o->values.mask, 4);
    if (o->seen & ROUTER)
        copy(to->gateway, o->values.gateway, 4);
    if (o->seen & DNS)
        copy(to->dns, o->values.dns, 4);
    if (o->seen & LEASE)
        to->seconds = o->values.seconds;
}

void genisis_dhcp_acquire(const struct genisis_dhcp_io *io, const unsigned char mac[6],
                          uint32_t xid, struct genisis_dhcp_lease *l)
{
    zero(l, (unsigned)sizeof *l);
    l->status = GENISIS_DHCP_IO;
    l->xid = xid;
    if (!io || !io->send || !io->receive || !io->milliseconds || !io->idle || !xid)
        return;
    unsigned char packet[GENISIS_DHCP_PACKET], source[4];
    struct options o;
    uint32_t start = io->milliseconds(io->context);
    unsigned state = 1, mask_seen = 0, polls = 0;
    for (unsigned attempt = 0; attempt < 3u; ++attempt)
    {
        unsigned timeout = (4000u << attempt) + ((xid >> (attempt * 8u)) % 2001u) - 1000u;
        unsigned elapsed = (io->milliseconds(io->context) - start) / 1000u;
        unsigned size = request(packet, state, mac, xid, l, elapsed);
        notify(io, state);
        if (!io->send(io->context, broadcast, 67, packet, size))
            return;
        uint32_t sent = io->milliseconds(io->context);
        while (io->milliseconds(io->context) - sent < timeout)
        {
            if (io->milliseconds(io->context) - start >= 30000u)
            {
                l->status = GENISIS_DHCP_TIMEOUT;
                return;
            }
            if (++polls > 10000u)
                return; /* A broken/frozen clock cannot hang firmware. */
            unsigned port = 0;
            int count = io->receive(io->context, source, &port, packet, sizeof packet);
            if (count < 0)
                return;
            if (count > 0)
            {
                if (port != 67u || !unicast(source) ||
                    !reply(packet, (unsigned)count, mac, xid, &o) ||
                    (state == 3u && !equal(o.values.server, l->server, 4)))
                    ++l->ignored;
                else if (state == 1u && o.type == 2u)
                {
                    merge(l, &o);
                    mask_seen = o.seen & MASK;
                    notify(io, GENISIS_DHCP_OFFER);
                    state = 3;
                    attempt = (unsigned)-1;
                    break; /* New bounded request phase. */
                }
                else if (state == 3u && o.type == 6u)
                {
                    l->status = GENISIS_DHCP_NAK;
                    return;
                }
                else if (state == 3u && o.type == 5u)
                {
                    if (!equal(o.values.ip, l->ip, 4) || !(o.seen & LEASE) ||
                        !((o.seen & MASK) || mask_seen))
                    {
                        ++l->ignored;
                    }
                    else
                    {
                        merge(l, &o);
                        l->status = GENISIS_DHCP_BOUND;
                        notify(io, GENISIS_DHCP_ACK);
                        return;
                    }
                }
                else
                    ++l->ignored;
            }
            if (!io->idle(io->context))
                return;
        }
    }
    l->status = GENISIS_DHCP_TIMEOUT;
}

int genisis_dhcp_release(const struct genisis_dhcp_io *io, const unsigned char mac[6],
                         const struct genisis_dhcp_lease *l)
{
    if (l->status != GENISIS_DHCP_BOUND)
        return 0;
    unsigned char packet[GENISIS_DHCP_PACKET];
    unsigned size = request(packet, 7, mac, l->xid, l, 0);
    return io->send(io->context, l->server, 67, packet, size);
}
