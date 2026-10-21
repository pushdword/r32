#ifndef GENISIS_W5500_H
#define GENISIS_W5500_H
#include "pmod.h"

enum genisis_w5500_status
{
    GENISIS_W5500_ABSENT = 0,
    GENISIS_W5500_READY = 1,
    GENISIS_W5500_VERSION = 2,
    GENISIS_W5500_TRANSPORT = 3,
    GENISIS_W5500_TIMEOUT = 4
};

struct genisis_w5500
{
    uint32_t status, version, phy, link, speed100, full_duplex, interrupt;
};

/* Reset + read common VERSIONR/PHYCFGR only. No MAC/IP/DHCP/socket traffic. */
void genisis_w5500_probe(struct genisis_pmod *bus, struct genisis_w5500 *nic);
/* Read PHY status without resetting the NIC. POST bounds the negotiation
 * wait and leaves sockets closed. DHCP runs from the setup network test. */
int genisis_w5500_link(struct genisis_pmod *bus, struct genisis_w5500 *nic, unsigned timeout_ms);
int genisis_w5500_read(struct genisis_pmod *bus, unsigned block, unsigned address,
                       unsigned char *data, unsigned size);
int genisis_w5500_write(struct genisis_pmod *bus, unsigned block, unsigned address,
                        const unsigned char *data, unsigned size);
/* Minimal polled UDP socket0 for the explicit setup test. Default 2KiB RX/TX,
 * bounded waits, stable 16-bit counts, wrap-safe buffer pointers. No heap/IRQ. */
int genisis_w5500_udp_open(struct genisis_pmod *bus, const unsigned char mac[6], unsigned port);
int genisis_w5500_udp_send(struct genisis_pmod *bus, const unsigned char ip[4], unsigned port,
                           const unsigned char *data, unsigned size);
int genisis_w5500_udp_receive(struct genisis_pmod *bus, unsigned char ip[4], unsigned *port,
                              unsigned char *data, unsigned capacity);
int genisis_w5500_config(struct genisis_pmod *bus, const unsigned char ip[4],
                         const unsigned char mask[4], const unsigned char gateway[4]);
int genisis_w5500_udp_close(struct genisis_pmod *bus);
#endif
