/* UART block protocol for R32 FAT images. Writes require checked requests. */
#include "hal.h"
#include "post.h"
#include "video.h"
#include "sd.h"
extern int r32_sd_write(uintptr_t, const struct genisis_sd_card *, unsigned, const unsigned char *);
extern void genisis_r32_reset(void);
static unsigned char data[512], verify[512], header[24];
static struct genisis_sd_card card;
static struct genisis_post_result post;
static volatile unsigned *const uart = (volatile unsigned *)0xf0000000u;

static unsigned word(const unsigned char *p)
{
    return (unsigned)p[0] | (unsigned)p[1] << 8 | (unsigned)p[2] << 16 | (unsigned)p[3] << 24;
}

static void store(unsigned char *p, unsigned n)
{
    for (unsigned i = 0; i < 4; i++)
        p[i] = n >> (8 * i);
}

static unsigned crc_byte32(unsigned c, unsigned char b)
{
    c ^= b;
    for (unsigned i = 0; i < 8; i++)
        c = (c >> 1) ^ ((0u - (c & 1u)) & 0xedb88320u);
    return c;
}

static unsigned checksum(unsigned n)
{
    unsigned c = ~0u;
    for (unsigned i = 0; i < 20; i++)
        c = crc_byte32(c, header[i]);
    for (unsigned i = 0; i < n; i++)
        c = crc_byte32(c, data[i]);
    return ~c;
}

static void tx(unsigned c)
{
    while (!(uart[1] & 1u))
    {
    }
    *(volatile unsigned char *)uart = (unsigned char)c;
}

static void response(unsigned op, unsigned seq, unsigned lba, unsigned status, unsigned n)
{
    header[0] = 'R';
    header[1] = '3';
    header[2] = 'S';
    header[3] = 'D';
    header[4] = 1;
    header[5] = op | 128;
    header[6] = n;
    header[7] = n >> 8;
    store(header + 8, seq);
    store(header + 12, lba);
    store(header + 16, status);
    store(header + 20, checksum(n));
    for (unsigned i = 0; i < 24; i++)
        tx(header[i]);
    for (unsigned i = 0; i < n; i++)
        tx(data[i]);
}

static void hex(unsigned n)
{
    for (unsigned s = 32; s;)
    {
        s -= 4;
        unsigned b = n >> s & 15;
        genisis_hal_putc(b < 10 ? '0' + b : 'A' + b - 10);
    }
}

void genisis_r32_recovery(void)
{
    const struct genisis_platform *p = genisis_hal_platform();
    if (!p)
    {
        genisis_hal_puts("R32 BOARD ERROR HWDT\r\n");
        for (;;)
            __asm__ volatile("wfi");
    }
    if (p->video_base)
        genisis_video_start(p->video_base);
    genisis_hal_puts("GENISIS / R32 ISA v1 / board boot\r\n");
    if (!genisis_post_run(p, &post))
    {
        genisis_hal_puts("R32 BOARD ERROR POST ");
        hex(post.error);
        genisis_hal_putc(' ');
        hex(post.address);
        genisis_hal_putc(' ');
        hex(post.expected);
        genisis_hal_putc(' ');
        hex(post.actual);
        genisis_hal_puts("\r\n");
        for (;;)
            __asm__ volatile("wfi");
    }
    genisis_hal_puts("R32 BOARD POST PASS\r\n");
    if (!p->spi_base || !genisis_sd_identify(p->spi_base, &card))
    {
        genisis_hal_puts("R32 BOARD ERROR SD ");
        hex(card.status);
        genisis_hal_puts("\r\n");
        for (;;)
            __asm__ volatile("wfi");
    }
    genisis_hal_puts("R32 SD READY BLOCKS ");
    hex(card.blocks);
    genisis_hal_puts("\r\n");
    /* Opt in after the strict legacy POST. QEMU and board both advertise UAF1. */
    /* FIFOs are active in the shared X32 hardware even in legacy status mode.
  * Its feature opt-in is sticky until reset. Preserve legacy status for the
  * repeated shared Genisis UART POST during the subsequent boot handoff. */
    unsigned fifo = 0;
    for (;;)
    {
        unsigned matched = 0;
        while (matched != 4)
        {
            unsigned c = (unsigned)genisis_hal_get_byte(0);
            if (c == (unsigned char)"R3SD"[matched])
                header[matched++] = c;
            else
                matched = c == 'R' ? 1 : 0;
        }
        for (unsigned i = 4; i < 24; i++)
            header[i] = (unsigned char)genisis_hal_get_byte(0);
        unsigned n = (unsigned)header[6] | (unsigned)header[7] << 8, op = header[5],
                 seq = word(header + 8), lba = word(header + 12), code = 0;
        if (n > 512)
        {
            response(op, seq, lba, 0x100, 0);
            continue;
        }
        for (unsigned i = 0; i < n; i++)
            data[i] = (unsigned char)genisis_hal_get_byte(0);
        if (header[4] != 1 || word(header + 16) || checksum(n) != word(header + 20))
        {
            response(op, seq, lba, 0x101, 0);
            continue;
        }
        if (op == 3 && n == 0)
        {
            store(data, card.blocks);
            store(data + 4, card.high_capacity);
            response(op, seq, lba, 0, 8);
        }
        else if (op == 1 && n == 0)
        {
            code = genisis_sd_read(p->spi_base, &card, lba, data);
            response(op, seq, lba, code == GENISIS_SD_READY ? 0 : code,
                     code == GENISIS_SD_READY ? 512 : 0);
        }
        else if (op == 2 && n == 512)
        {
            code = r32_sd_write(p->spi_base, &card, lba, data);
            if (code == GENISIS_SD_READY)
            {
                code = genisis_sd_read(p->spi_base, &card, lba, verify);
                if (code == GENISIS_SD_READY)
                    for (unsigned i = 0; i < 512; i++)
                        if (data[i] != verify[i])
                        {
                            code = 0x102;
                            break;
                        }
            }
            response(op, seq, lba, code == GENISIS_SD_READY ? 0 : code, 0);
        }
        else if (op == 4 && n == 0)
        {
            response(op, seq, lba, 0, 0);
            if (fifo)
                while (!(uart[1] & (1u << 4)))
                {
                }
            *(volatile unsigned char *)(uart + 2) = 0;
            genisis_r32_reset();
        }
        else
            response(op, seq, lba, 0x103, 0);
    }
}
