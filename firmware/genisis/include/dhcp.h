/* Bounded DHCPv4 acquisition through transport callbacks.
 * The BIOS network test performs no background renewal or DNS resolution. */
#ifndef GENISIS_DHCP_H
#define GENISIS_DHCP_H
#include <stdint.h>
#define GENISIS_DHCP_PACKET 576u

enum genisis_dhcp_status
{
    GENISIS_DHCP_IDLE = 0,
    GENISIS_DHCP_BOUND = 1,
    GENISIS_DHCP_TIMEOUT = 2,
    GENISIS_DHCP_IO = 3,
    GENISIS_DHCP_NAK = 4
};

enum genisis_dhcp_event
{
    GENISIS_DHCP_DISCOVER = 1,
    GENISIS_DHCP_OFFER = 2,
    GENISIS_DHCP_REQUEST = 3,
    GENISIS_DHCP_ACK = 4
};

struct genisis_dhcp_lease
{
    unsigned char ip[4], mask[4], gateway[4], dns[4], server[4];
    uint32_t status, seconds, xid, ignored;
};

struct genisis_dhcp_io
{
    void *context;
    int (*send)(void *, const unsigned char *, unsigned, const unsigned char *, unsigned);
    int (*receive)(void *, unsigned char *, unsigned *, unsigned char *, unsigned);
    uint32_t (*milliseconds)(void *);
    int (*idle)(void *);
    void (*event)(void *, unsigned);
};

void genisis_dhcp_acquire(const struct genisis_dhcp_io *io, const unsigned char mac[6],
                          uint32_t xid, struct genisis_dhcp_lease *lease);
/* DHCPRELEASE is unicast. Caller first applies the acquired IP/mask/gateway,
 * then releases and clears the temporary socket/config even on send failure. */
int genisis_dhcp_release(const struct genisis_dhcp_io *io, const unsigned char mac[6],
                         const struct genisis_dhcp_lease *lease);
#endif
