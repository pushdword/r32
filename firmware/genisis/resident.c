/* All code, constants, data and stack used while testing SDRAM stay in BRAM.
 * The GUI is reloaded from the R32-only TF before returning to its caller. */
#include "genisis.h"
#include "hal.h"
#include "post.h"
#include "video.h"
#include "sd.h"
#include "fat_ro.h"
extern int main(void);
extern void genisis_r32_recovery(void);
static struct genisis_sd_card resident_card;

static int sector(void *p, uint32_t lba, unsigned char *b)
{
    return genisis_sd_read((uintptr_t)p, &resident_card, lba, b) == GENISIS_SD_READY;
}

static uint32_t crc_byte(uint32_t c, unsigned char v)
{
    static const uint32_t t[16] = {0,           0x1db71064u, 0x3b6e20c8u, 0x26d930acu,
                                   0x76dc4190u, 0x6b6b51f4u, 0x4db26158u, 0x5005713cu,
                                   0xedb88320u, 0xf00f9344u, 0xd6d6a3e8u, 0xcb61b38cu,
                                   0x9b64c2b0u, 0x86d3d2d4u, 0xa00ae278u, 0xbdbdf21cu};
    c ^= v;
    c = c >> 4 ^ t[c & 15];
    return c >> 4 ^ t[c & 15];
}

void genisis_bios_progress(unsigned phase, uint32_t done, uint32_t total)
{
    static const char *const names[] = {"CPU",
                                        "UART",
                                        "RAM DATA",
                                        "RAM ADDRESS",
                                        "RAM PATTERN1 WRITE",
                                        "RAM PATTERN1 VERIFY",
                                        "RAM PATTERN2 WRITE",
                                        "RAM PATTERN2 VERIFY",
                                        "TIMER"};
    if (phase > 8)
        return;
    genisis_hal_puts(names[phase]);
    char d[10];
    unsigned n = 0;
    do
    {
        d[n++] = '0' + done % 10;
        done /= 10;
    } while (done);
    genisis_hal_putc(' ');
    while (n)
        genisis_hal_putc(d[--n]);
    genisis_hal_puts(" bytes\r\n");
    (void)total;
}

static int load(void)
{
    const struct genisis_platform *p = genisis_hal_platform();
    if (!p || !p->spi_base || !genisis_sd_identify(p->spi_base, &resident_card))
        return 0;
    struct fat_ro fs;
    struct fat_ro_file file;
    struct genisis_image h;
    if (!fat_ro_mount(&fs, sector, (void *)p->spi_base, resident_card.blocks) ||
        !fat_ro_open(&fs, "/boot/genisis.r32", &file) || file.directory || file.size < 32 ||
        fat_ro_read(&fs, &file, (unsigned char *)&h, 32) != 32)
        return 0;
    if (h.magic != GENISIS_MAGIC || h.version != 1 || h.load != 0x13f00000u || h.entry != h.load ||
        !h.file_bytes || (h.file_bytes & 3) || h.file_bytes > 0x80000u ||
        h.memory_bytes != h.file_bytes || h.flags || file.size != 32 + h.file_bytes)
        return 0;
    unsigned char *dest = (unsigned char *)h.load;
    uint32_t c = ~0u;
    for (unsigned off = 0; off < h.file_bytes;)
    {
        unsigned n = h.file_bytes - off;
        if (n > 512)
            n = 512;
        if (fat_ro_read(&fs, &file, dest + off, n) != (int)n)
            return 0;
        for (unsigned i = 0; i < n; i++)
            c = crc_byte(c, dest[off + i]);
        off += n;
    }
    if (~c != h.crc32)
        return 0;
    c = ~0u;
    for (unsigned i = 0; i < h.file_bytes; i++)
        c = crc_byte(c, *(volatile unsigned char *)(h.load + i));
    if (~c != h.crc32)
        return 0;
    __asm__ volatile("fence.i" ::: "memory");
    return 1;
}

void genisis_bios_reload(void)
{
    genisis_hal_puts("GENISIS R32 GUI TF LOAD\r\n");
    if (!load())
    {
        genisis_hal_puts("GENISIS R32 GUI HEADER/CRC ERROR - BRAM RECOVERY\r\n");
        genisis_r32_recovery();
        for (;;)
            __asm__ volatile("wfi");
    }
    genisis_hal_puts("GENISIS R32 GUI VERIFIED IN SDRAM\r\n");
}

int genisis_bios_memory_test(const struct genisis_platform *p, struct genisis_post_result *r,
                             uint32_t bytes)
{
    struct genisis_post_options o = {bytes, genisis_bios_progress};
    int ok = genisis_post_run_ex(p, r, &o);
    genisis_bios_reload();
    return ok;
}

void genisis_r32_reset(void)
{
    const struct genisis_platform *p = genisis_hal_platform();
    if (p && p->video_base)
        genisis_video_start(p->video_base);
    genisis_hal_puts("GENISIS R32 GUI STAGE0 / M UART MAINTENANCE\r\n");
    if (!p)
    {
        genisis_hal_puts("GENISIS R32 GUI ERROR HWDT\r\n");
        for (;;)
            __asm__ volatile("wfi");
    }
    volatile unsigned *const clock = (volatile unsigned *)0xf0007024u;
    unsigned first = *clock;
    while ((unsigned)(*clock - first) < p->clock_hz)
    {
        if (genisis_hal_read32(0xf0000004u) & 2u)
        {
            int k = genisis_hal_get_byte(0);
            if (k == 'M' || k == 'm')
            {
                genisis_r32_recovery();
                return;
            }
        }
    }
    struct genisis_post_result r;
    struct genisis_post_options o = {0, genisis_bios_progress};
    if (!genisis_post_run_ex(p, &r, &o))
    {
        genisis_hal_puts("GENISIS R32 STAGE0 POST FAIL\r\n");
        genisis_r32_recovery();
        return;
    }
    genisis_bios_reload();
    (void)main();
}
