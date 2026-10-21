/* Genisis stage0: arranque/debug em BRAM e loader UART para SDRAM.
 * Sem libc/heap: a imagem de arranque permanece pequena e independente do OS. */
#include "genisis.h"
#include "hal.h"
#include "post.h"
#include "description.h"
#ifdef GENISIS_BOARD_IO
#include "video.h"
#include "sd.h"
#include "input.h"
#include "ui.h"
#include "bios_resident.h"
#include "fat_ro.h"
static struct genisis_sd_card sd_card;
#ifdef GENISIS_PMOD_DRIVERS
#include "rtc.h"
#include "w5500.h"
#include "setup.h"
static struct genisis_rtc rtc;
static struct genisis_w5500 nic;
#endif
#endif

volatile struct genisis_boot_info genisis_info;

/* Vista por palavras e vista por campos têm a mesma representação no ABI.
 * A union evita tratar membros separados de uma struct como um array C. */
static union
{
    struct genisis_image header;
    uint32_t words[8];
} image;

_Static_assert(sizeof(struct genisis_image) == 32, "Genisis image header ABI");
_Static_assert(sizeof(struct genisis_boot_info) == 56, "Genisis boot_info ABI");
static unsigned loaded;
struct genisis_post_result genisis_post;
static unsigned post_ok;
#ifdef GENISIS_BOARD_IO
/* Only the simulation ROM may reduce the optional diagnostic span/window. */
#ifndef GENISIS_SETUP_FRAMES
#define GENISIS_SETUP_FRAMES 300u
#endif
static uint32_t ram_diagnostic_bytes(const struct genisis_platform *p)
{
#ifdef GENISIS_POST_TEST_BYTES
    (void)p;
    return GENISIS_POST_TEST_BYTES;
#else
    return p ? p->memory_bytes : 0;
#endif
}
#endif

/* Receção por polling: o protocolo pede um byte de cada vez com ACK=06,
 * evitando overrun no RX de uma posição durante stores e CRC na SDRAM. */
static int get_byte(unsigned bounded)
{
    return genisis_hal_get_byte(bounded);
}

/* A alteração de fase fica observável em RAM e na consola desde o stage0. */
static void stage(unsigned value, const char *message)
{
    genisis_info.stage = value;
    genisis_hal_puts(message);
}

/* Diagnósticos fixed-width permitem analisar logs sem printf/libc no boot. */
static void hex(uint32_t value)
{
    for (unsigned shift = 32; shift;)
    {
        shift -= 4;
        unsigned digit = (value >> shift) & 15u;
        genisis_hal_putc((unsigned char)(digit < 10 ? '0' + digit : 'A' + digit - 10));
    }
}

#ifdef GENISIS_BOARD_IO
/* No libc is needed for human-readable sizes/clocks in the boot console. */
static void decimal(uint32_t value)
{
    unsigned char digits[10];
    unsigned count = 0;
    do
    {
        digits[count++] = (unsigned char)('0' + value % 10u);
        value /= 10u;
    } while (value);
    while (count)
        genisis_hal_putc(digits[--count]);
}

static void cpu_info(const struct genisis_platform *p)
{
    const struct genisis_cpu_description *c = genisis_hal_cpu_description();
    genisis_hal_puts("CPU: ");
    genisis_hal_puts(c->name);
    genisis_hal_puts("\r\nARCH: R32 / 32 BIT / LITTLE-ENDIAN / SIX-STAGE\r\n");
    genisis_hal_puts("ISA VERSION: ");
    decimal(c->version);
    genisis_hal_puts(" / FORMS: ");
    decimal(c->forms);
    genisis_hal_puts("\r\nFEATURES: MUL MULHI DIV/MOD BITS MMU USER/KERNEL IRQ/SRET LR/SC");
    if (c->features & R32_CPU_FPU32)
        genisis_hal_puts(" FPU32");
    genisis_hal_puts("\r\nICACHE: OFF / DCACHE: OFF\r\nCPU CLOCK: ");
    decimal(genisis_r32_cpu_hz() / 1000000);
    genisis_hal_puts(" MHz / SYS CLOCK: ");
    decimal(p ? p->clock_hz / 1000000 : 0);
    genisis_hal_puts(" MHz\r\nCPU CORES: ");
    decimal(p ? p->core_count : 0);
    genisis_hal_puts("\r\n");
}

static void platform_info(const struct genisis_platform *p)
{
    if (!p)
        return;
    genisis_hal_puts("BOARD: ");
    genisis_hal_puts(p->name);
    genisis_hal_puts("\r\n");
    genisis_hal_puts("BOOT ROM/BRAM: ");
    decimal(p->bram_bytes / 1024u);
    genisis_hal_puts(" KiB\r\n");
    genisis_hal_puts("SDRAM: ");
    decimal(p->memory_bytes / 1024u);
    genisis_hal_puts(" KiB / 2 RANKS\r\n");
    genisis_hal_puts("UART: ");
    decimal(p->uart_baud);
    genisis_hal_puts(" BAUD / 8N1 / DEBUG CONSOLE\r\n");
    if (p->integrated & GENISIS_TIMER)
        genisis_hal_puts("TIMER: INTEGRATED / IRQ 0 / DISABLED AT RESET\r\n");
    if (p->integrated & GENISIS_SPI)
        genisis_hal_puts("TF SPI: INTEGRATED / READ-ONLY IDENTIFICATION\r\n");
}

/* Update one progress line on both consoles with CR.
 * Advance counters after completed memory transfers. */
static void post_progress(unsigned phase, uint32_t done, uint32_t total)
{
    static const char *const names[] = {
        "CPU ARITHMETIC",      "UART STATUS",          "RAM DATA BUS",
        "RAM ADDRESS BUS",     "RAM PATTERN 1 WRITE",  "RAM PATTERN 1 VERIFY",
        "RAM PATTERN 2 WRITE", "RAM PATTERN 2 VERIFY", "TIMER RESET STATE"};
    genisis_ui_progress(phase, done, total);
    genisis_hal_putc('\r');
    genisis_hal_puts(names[phase]);
    genisis_hal_puts(": ");
    if (phase >= GENISIS_PHASE_WRITE_ADDRESS && phase <= GENISIS_PHASE_READ_INVERSE)
    {
        decimal(done / 1024u);
        genisis_hal_puts(" / ");
        decimal(total / 1024u);
        genisis_hal_puts(" KiB");
    }
    else
    {
        decimal(done);
        genisis_hal_puts(" / ");
        decimal(total);
    }
    genisis_hal_puts(done == total ? "  OK          \r\n" : "  TESTING     ");
}
#endif

/* Erro invalida sempre a imagem: G nunca executa um download incompleto. */
static void failure(unsigned error)
{
    loaded = 0;
    genisis_info.error = error;
    genisis_info.stage = 0xffu;
    genisis_hal_puts("GENISIS ERROR ");
    hex(error);
    genisis_hal_puts("\r\n");
}

/* CRC32 refletido com polinómio EDB88320. */
static uint32_t crc_byte(uint32_t crc, unsigned char byte)
{
    crc ^= byte;
    for (unsigned bit = 0; bit < 8; ++bit)
        crc = (crc >> 1) ^ ((crc & 1u) ? 0xedb88320u : 0);
    return crc;
}

/* GUI firmware only: keep the installed resident CRC helper and its ABI.
 * Both TF integrity passes use the same reflected polynomial, two nibbles
 * per byte instead of eight bit rounds. The table is read-only SDRAM. */
static const uint32_t tf_crc_nibble[16] = {0x00000000u, 0x1db71064u, 0x3b6e20c8u, 0x26d930acu,
                                           0x76dc4190u, 0x6b6b51f4u, 0x4db26158u, 0x5005713cu,
                                           0xedb88320u, 0xf00f9344u, 0xd6d6a3e8u, 0xcb61b38cu,
                                           0x9b64c2b0u, 0x86d3d2d4u, 0xa00ae278u, 0xbdbdf21cu};

static __attribute__((always_inline)) inline uint32_t tf_crc_byte(uint32_t crc, unsigned char byte)
{
    crc ^= byte;
    crc = (crc >> 4) ^ tf_crc_nibble[crc & 15u];
    return (crc >> 4) ^ tf_crc_nibble[crc & 15u];
}

/* Todos os limites são validados sem somas que possam dar wrap.
 * A entrada tem de cair em bytes realmente recebidos, não na zona BSS. */
static unsigned valid_header(void)
{
    return image.header.magic == GENISIS_MAGIC && image.header.version == GENISIS_VERSION &&
           !image.header.flags && image.header.load >= GENISIS_LOAD_MIN &&
           image.header.load < GENISIS_LOAD_END && !(image.header.load & 3u) &&
           image.header.file_bytes && image.header.file_bytes <= image.header.memory_bytes &&
           image.header.memory_bytes <= GENISIS_LOAD_END - image.header.load &&
           !(image.header.entry & 3u) && image.header.entry >= image.header.load &&
           image.header.entry - image.header.load <= image.header.file_bytes &&
           image.header.file_bytes - (image.header.entry - image.header.load) >= 4u;
}

/* L recebe header+payload, valida CRC e limpa BSS antes de publicar LOADED.
 * Só depois desta publicação G pode transferir controlo para o kernel. */
static void load_image(void)
{
    loaded = 0;
    genisis_info.error = 0;
    stage(3, "GENISIS HEADER\r\n");
    uint32_t *fields = image.words;
    for (unsigned i = 0; i < 8; ++i)
    {
        uint32_t value = 0;
        for (unsigned byte = 0; byte < 4; ++byte)
        {
            genisis_hal_putc(6);
            int next = get_byte(1);
            if (next < 0)
            {
                failure(2);
                return;
            }
            value |= (uint32_t)next << (byte * 8);
        }
        fields[i] = value;
    }
    if (!valid_header())
    {
        failure(3);
        return;
    }
    stage(4, "GENISIS LOAD\r\n");
    volatile unsigned char *destination = (volatile unsigned char *)image.header.load;
    uint32_t crc = 0xffffffffu;
    for (unsigned i = 0; i < image.header.file_bytes; ++i)
    {
        genisis_hal_putc(6);
        int next = get_byte(1);
        if (next < 0)
        {
            failure(2);
            return;
        }
        genisis_hal_write8((uintptr_t)destination + i, (unsigned char)next);
        crc = crc_byte(crc, (unsigned char)next);
    }
    if ((crc ^ 0xffffffffu) != image.header.crc32)
    {
        failure(4);
        return;
    }
    for (unsigned i = image.header.file_bytes; i < image.header.memory_bytes; ++i)
        genisis_hal_write8((uintptr_t)destination + i, 0);
    genisis_info.image_start = image.header.load;
    genisis_info.image_end = image.header.load + image.header.memory_bytes;
    genisis_info.entry = image.header.entry;
    genisis_info.source = 1; /* Origem UART. */
    loaded = 1;
    stage(5, "GENISIS LOADED\r\n");
}

struct tf_reader
{
    uintptr_t spi;
    const struct genisis_sd_card *card;
};

static int tf_sector(void *context, uint32_t block, unsigned char *data)
{
    const struct tf_reader *r = context;
    return genisis_sd_read(r->spi, r->card, block, data) == GENISIS_SD_READY;
}

static int tf_blocks(void *context, uint32_t block, uint32_t count, unsigned char *data)
{
    const struct tf_reader *r = context;
    return genisis_sd_read_blocks(r->spi, r->card, block, count, data) == GENISIS_SD_READY;
}

/* Progress state stays on the BRAM stack, preserving resident globals/ABI.
 * Work = payload write + payload readback + BSS clear bytes. Percent is a
 * completed-work fraction, not a time estimate. CRC must pass before READY. */
struct tf_progress
{
    uint32_t work;
    unsigned percent, phase;
};

static void post_screen(const struct genisis_platform *p, int complete);

static void tf_progress(struct tf_progress *s, unsigned phase, uint32_t done, uint32_t total,
                        uint32_t base)
{
    unsigned previous = s->percent;
    if (s->work && phase != GENISIS_BOOT_ERROR)
    {
        uint32_t completed = base + done;
        /* ceil(work * next_percent / 100), without a 32-bit multiply overflow
         * and without requiring a 64-bit runtime in this freestanding loader. */
        while (s->percent < 99)
        {
            unsigned next = s->percent + 1;
            uint32_t threshold = (s->work / 100) * next + ((s->work % 100) * next + 99) / 100;
            if (completed < threshold)
                break;
            s->percent = next;
        }
    }
    if (phase == GENISIS_BOOT_READY)
        s->percent = 100;
    if (previous == s->percent && s->phase == phase)
        return;
    s->phase = phase;
    genisis_ui_boot_progress(phase, done, total, s->percent);
    genisis_hal_puts("GENISIS BOOT ");
    decimal(s->percent);
    genisis_hal_puts("% ");
    genisis_hal_puts(genisis_ui_boot_phase(phase));
    if (total)
    {
        genisis_hal_puts(" ");
        decimal(done);
        genisis_hal_puts("/");
        decimal(total);
        genisis_hal_puts(" bytes");
    }
    genisis_hal_puts("\r\n");
}

static int tf_failure(struct tf_progress *s, unsigned error)
{
    failure(error);
    tf_progress(s, GENISIS_BOOT_ERROR, 0, 0, 0);
    return 0;
}

/* Filesystem code is SDRAM firmware. All new state is local: the installed
 * resident bootstrap/globals/BRAM ABI must remain byte-identical. */
static int load_tf_image(const struct genisis_platform *p)
{
    struct tf_progress progress = {0, 0, ~0u};
    loaded = 0;
    genisis_info.error = 0;
    post_screen(p, 1);
    tf_progress(&progress, GENISIS_BOOT_OPEN, 0, 0, 0);
    genisis_hal_puts("GENISIS TF: " GENISIS_TF_BOOT_PATH "\r\n");
    if (!p || sd_card.status != GENISIS_SD_READY)
        return tf_failure(&progress, 7);
    struct tf_reader reader = {p->spi_base, &sd_card};
    struct fat_ro fs;
    struct fat_ro_file file;
    if (!fat_ro_mount(&fs, tf_sector, &reader, sd_card.blocks))
        return tf_failure(&progress, 7);
    fat_ro_set_block_reader(&fs, tf_blocks);
    if (!fat_ro_open(&fs, GENISIS_TF_BOOT_PATH, &file) || file.directory || file.size < 32)
    {
        genisis_hal_puts("GENISIS TF: NO USABLE BOOT IMAGE / SETUP AVAILABLE\r\n");
        return tf_failure(&progress, 7);
    }
    tf_progress(&progress, GENISIS_BOOT_HEADER, 0, 32, 0);
    for (unsigned i = 0; i < 8; i++)
    {
        unsigned char bytes[4];
        if (fat_ro_read(&fs, &file, bytes, 4) != 4)
            return tf_failure(&progress, 7);
        image.words[i] = (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8) |
                         ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
    }
    if (!valid_header() || image.header.load != 0x10050000u ||
        image.header.memory_bytes > 0x10400000u - image.header.load ||
        image.header.file_bytes != file.size - 32u)
        return tf_failure(&progress, 3);
    progress.work = image.header.file_bytes + image.header.memory_bytes;
    stage(4, "GENISIS TF LOADING BOOT IMAGE\r\n");
    tf_progress(&progress, GENISIS_BOOT_READ, 0, image.header.file_bytes, 0);
    uint32_t crc = 0xffffffffu;
    for (unsigned done = 0; done < image.header.file_bytes;)
    {
        unsigned take = image.header.file_bytes - done;
        unsigned head = file.position & 511u;
        if (head && take > 512u - head)
            take = 512u - head;
        else if (take > 8192u)
            take = 8192u;
        /* The first480 bytes finish the header's sector. Subsequent8KiB
         * windows allow FAT to merge sectors and write directly into SDRAM. */
        unsigned char *destination = (unsigned char *)(uintptr_t)(image.header.load + done);
        if (fat_ro_read(&fs, &file, destination, take) != (int)take)
            return tf_failure(&progress, 7);
        for (unsigned i = 0; i < take; i++)
            crc = tf_crc_byte(crc, ((volatile unsigned char *)destination)[i]);
        done += take;
        tf_progress(&progress, GENISIS_BOOT_READ, done, image.header.file_bytes, 0);
    }
    if ((crc ^ 0xffffffffu) != image.header.crc32)
        return tf_failure(&progress, 4);
    tf_progress(&progress, GENISIS_BOOT_VERIFY, 0, image.header.file_bytes,
                image.header.file_bytes);
    crc = 0xffffffffu;
    for (unsigned i = 0; i < image.header.file_bytes; i += 4)
    {
        uint32_t word = genisis_hal_read32(image.header.load + i);
        for (unsigned j = 0; j < 4 && i + j < image.header.file_bytes; j++)
            crc = tf_crc_byte(crc, (unsigned char)(word >> (j * 8)));
        if (!((i + 4) & 511) || i + 4 >= image.header.file_bytes)
        {
            unsigned done = i + 4;
            if (done > image.header.file_bytes)
                done = image.header.file_bytes;
            tf_progress(&progress, GENISIS_BOOT_VERIFY, done, image.header.file_bytes,
                        image.header.file_bytes);
        }
    }
    if ((crc ^ 0xffffffffu) != image.header.crc32)
        return tf_failure(&progress, 4);
    unsigned bss = image.header.memory_bytes - image.header.file_bytes;
    tf_progress(&progress, GENISIS_BOOT_CLEAR, 0, bss, 2 * image.header.file_bytes);
    for (unsigned done = 0; done < bss;)
    {
        unsigned take = bss - done;
        if (take > 512)
            take = 512;
        for (unsigned i = 0; i < take; i++)
            genisis_hal_write8(image.header.load + image.header.file_bytes + done + i, 0);
        done += take;
        tf_progress(&progress, GENISIS_BOOT_CLEAR, done, bss, 2 * image.header.file_bytes);
    }
    genisis_info.image_start = image.header.load;
    genisis_info.image_end = image.header.load + image.header.memory_bytes;
    genisis_info.entry = image.header.entry;
    genisis_info.source = 2;
    loaded = 1;
    stage(5, "GENISIS TF IMAGE CRC AND SDRAM READBACK OK\r\n");
    tf_progress(&progress, GENISIS_BOOT_READY, progress.work, progress.work, 0);
    return 1;
}

/* Passa boot_info em a0 e salta para a entrada do kernel.
 * O kernel prepara a sua pilha e não regressa ao monitor. */
__attribute__((noreturn)) static void enter_kernel(void)
{
    stage(6, "GENISIS JUMP\r\n");
    genisis_hal_flush();
    genisis_hal_enter(image.header.entry, (const void *)&genisis_info);
}

/* Mostra o estado de arranque guardado pelo firmware. */
static void info(void)
{
    genisis_hal_puts("GENISIS INFO stage=");
    hex(genisis_info.stage);
    genisis_hal_puts(" error=");
    hex(genisis_info.error);
    genisis_hal_puts(" entry=");
    hex(genisis_info.entry);
    genisis_hal_puts(" post=");
    hex(genisis_post.error);
    genisis_hal_puts(" verified=");
    hex(genisis_post.passed);
    genisis_hal_puts("\r\n");
}

#ifdef GENISIS_BOARD_IO
/* Menu input is distinct from the binary UART loader: USB keys never enter
 * the download protocol. Only new presses are delivered by the event queue. */
static int poll_key(const struct genisis_platform *p)
{
    return genisis_input_poll(p);
}

static int wait_key(const struct genisis_platform *p)
{
    int value;
    do
    {
        value = poll_key(p);
    } while (value < 0);
    return value;
}

static void keyboard_info(const struct genisis_platform *p)
{
    if (!p || !(p->integrated & GENISIS_KEYBOARD))
    {
        genisis_hal_puts("USB KEYBOARD CONTROLLER NOT AVAILABLE\r\n");
        return;
    }
    unsigned status = genisis_hal_read32(p->keyboard_base + 4u);
    genisis_hal_puts(status & 2u ? "USB KEYBOARD: DETECTED\r\n" : "USB KEYBOARD: NOT DETECTED\r\n");
    genisis_hal_puts("USB: LOW-SPEED HID / DIRECT CONNECTION\r\nSTATUS: ");
    hex(status);
    genisis_hal_puts(" REPORTS: ");
    hex(genisis_hal_read32(p->keyboard_base + 16u));
    genisis_hal_puts("\r\n");
}
#ifdef GENISIS_PMOD_DRIVERS
static void two_digits(unsigned value)
{
    genisis_hal_putc((unsigned char)('0' + value / 10u));
    genisis_hal_putc((unsigned char)('0' + value % 10u));
}

static void pmod_info(void)
{
    genisis_hal_puts("RTC I2C 68: ");
    if (rtc.status == GENISIS_RTC_ABSENT)
        genisis_hal_puts("NOT DETECTED\r\n");
    else if (rtc.status == GENISIS_RTC_READY)
    {
        decimal(rtc.year);
        genisis_hal_putc('-');
        two_digits(rtc.month);
        genisis_hal_putc('-');
        two_digits(rtc.day);
        genisis_hal_putc(' ');
        two_digits(rtc.hour);
        genisis_hal_putc(':');
        two_digits(rtc.minute);
        genisis_hal_putc(':');
        two_digits(rtc.second);
        genisis_hal_puts(" UTC / DS3231 COMPATIBLE\r\n");
    }
    else if (rtc.status == GENISIS_RTC_UNSET)
        genisis_hal_puts("RESPONDS / TIME UNSET (OSF)\r\n");
    else if (rtc.status == GENISIS_RTC_INVALID)
        genisis_hal_puts("RESPONDS / INVALID CALENDAR\r\n");
    else
        genisis_hal_puts("BUS ERROR / TIMEOUT\r\n");
    genisis_hal_puts("ETHERNET W5500: ");
    if (nic.status == GENISIS_W5500_READY)
    {
        genisis_hal_puts("DETECTED / VERSION 04 / ");
        if (!nic.link)
            genisis_hal_puts("LINK DOWN\r\n");
        else
        {
            genisis_hal_puts(nic.speed100 ? "100 MBPS / " : "10 MBPS / ");
            genisis_hal_puts(nic.full_duplex ? "FULL DUPLEX\r\n" : "HALF DUPLEX\r\n");
        }
    }
    else if (nic.status == GENISIS_W5500_ABSENT)
        genisis_hal_puts("NOT DETECTED\r\n");
    else
    {
        genisis_hal_puts("PROBE ERROR ");
        decimal(nic.status);
        genisis_hal_puts("\r\n");
    }
}

static void pmod_probe(const struct genisis_platform *p)
{
    struct genisis_pmod bus;
    if (!(p->integrated & GENISIS_PMOD))
        return;
    if (!genisis_pmod_open(&bus, p->pmod_base, p->clock_hz))
    {
        genisis_hal_puts("PMOD1 CONTROLLER ERROR\r\n");
        return;
    }
    genisis_post.passed |= GENISIS_PMOD;
    genisis_rtc_probe(&bus, &rtc);
    genisis_w5500_probe(&bus, &nic);
    if (nic.status == GENISIS_W5500_READY)
    {
        genisis_hal_puts("ETHERNET: WAITING FOR LINK\r\n");
        if (!genisis_w5500_link(&bus, &nic, 3000))
            nic.status = GENISIS_W5500_TRANSPORT;
    }
    pmod_info();
}

static void pmod_refresh(const struct genisis_platform *p)
{
    struct genisis_pmod bus;
    if (!p || !(p->integrated & GENISIS_PMOD) ||
        !genisis_pmod_open(&bus, p->pmod_base, p->clock_hz))
        return;
    genisis_rtc_probe(&bus, &rtc);
    if (nic.status == GENISIS_W5500_READY)
        (void)genisis_w5500_link(&bus, &nic, 0);
}
#endif
/* Sample the free-running frame counter without enabling timer IRQs.
 * The counter runs without an attached monitor. Bound polling and skip the
 * sample on PLL unlock so a stopped counter cannot block serial boot. */
static int setup_window(const struct genisis_platform *p, int video_ok)
{
    genisis_hal_puts("PRESS 8 FOR SETUP - 5 SECONDS / USB KEYBOARD OR UART\r\n");
    int key = poll_key(p);
    if (key >= 0)
        return key;
    if (!video_ok || !GENISIS_SETUP_FRAMES)
        return -1;
    uint32_t first = genisis_hal_read32(p->video_base + 20u);
    unsigned budget = 4000000u;
    while (budget--)
    {
        key = poll_key(p);
        if (key >= 0)
            return key;
        if (!(genisis_hal_read32(p->video_base + 4u) & 1u))
            break;
        if (genisis_hal_read32(p->video_base + 20u) - first >= GENISIS_SETUP_FRAMES)
            break;
    }
    return -1;
}

static void ram_diagnostic(const struct genisis_platform *p)
{
    /* Invalidate the UART image before destructive RAM writes.
     * A failed test can leave its contents corrupted. */
    loaded = 0;
    genisis_info.image_start = genisis_info.image_end = genisis_info.entry = 0;
    if (p && p->core_count > 1 && (p->integrated & GENISIS_SMP))
        genisis_hal_write32(p->smp_base + 24u, 2u);
    uint32_t peripherals = genisis_post.passed & (GENISIS_VIDEO | GENISIS_SPI | GENISIS_KEYBOARD |
                                                  GENISIS_SMP | GENISIS_PMOD);
    /* This callback and every callee of POST live in BRAM. The test includes
     * the firmware's SDRAM pages, so GUI text/rodata must be reloaded before
     * returning to the graphical caller. All globals and stack remain BRAM. */
    struct genisis_post_options options = {ram_diagnostic_bytes(p), genisis_bios_progress};
    genisis_hal_puts("FULL RAM TEST - 2 PATTERNS / TAKES SEVERAL MINUTES\r\n");
#ifdef GENISIS_POST_TEST_BYTES
    genisis_hal_puts("SIMULATION POST SPAN: ");
    decimal(options.full_memory_bytes);
    genisis_hal_puts(" BYTES\r\n");
#endif
    post_ok = (unsigned)genisis_bios_memory_test(p, &genisis_post, options.full_memory_bytes);
    genisis_post.passed |= peripherals;
    if (post_ok)
    {
        genisis_info.error = 0;
        genisis_info.stage = 2;
        genisis_hal_puts("MEMORY VERIFIED: ");
        decimal(genisis_post.full_bytes / 1024u);
        genisis_hal_puts(" KiB / ");
        decimal(genisis_post.full_patterns);
        genisis_hal_puts(" FULL PATTERNS\r\n");
    }
    else
    {
        genisis_hal_puts("RAM TEST FAIL address=");
        hex((uint32_t)genisis_post.address);
        genisis_hal_puts(" expected=");
        hex(genisis_post.expected);
        genisis_hal_puts(" actual=");
        hex(genisis_post.actual);
        genisis_hal_puts("\r\n");
        failure(6);
    }
}

static struct genisis_ui_state ui_state(const struct genisis_platform *p)
{
    struct genisis_ui_state s = {p, &sd_card, 0, 0, &genisis_post};
#ifdef GENISIS_PMOD_DRIVERS
    s.rtc = &rtc;
    s.nic = &nic;
#endif
    return s;
}

static void post_screen(const struct genisis_platform *p, int complete)
{
    struct genisis_ui_state s = ui_state(p);
    genisis_ui_post(&s, complete);
}

static void setup_menu(const struct genisis_platform *p, unsigned page)
{
    unsigned selected = 0;
#ifdef GENISIS_PMOD_DRIVERS
    pmod_refresh(p);
#endif
    for (;;)
    {
        struct genisis_ui_state s = ui_state(p);
        genisis_ui_menu(&s, page, selected);
        genisis_hal_puts(
            "GENISIS BIOS SETUP\r\n1 CONTINUE / ESC RETURN\r\n2 FULL RAM TEST\r\n3 CPU INFORMATION\r\n4 HARDWARE INFORMATION\r\n");
#ifdef GENISIS_PMOD_DRIVERS
        genisis_hal_puts("5 NETWORK TEST (DHCP)\r\n6 DATE AND TIME (RTC)\r\n");
#endif
        genisis_hal_puts(
            "ARROWS: PAGE/ITEM / ENTER: OPEN / F1 HELP / F5 REFRESH / F10 EXIT\r\nPAGE: ");
        decimal(page + 1);
        genisis_hal_puts(" ITEM: ");
        decimal(selected + 1);
        genisis_hal_puts("\r\nSELECT: ");
        int key = wait_key(p);
        genisis_hal_puts("\r\n");
        if (key == GENISIS_KEY_LEFT || key == GENISIS_KEY_RIGHT)
        {
            page = (page + (key == GENISIS_KEY_LEFT ? 5 : 1)) % 6;
            selected = 0;
            continue;
        }
        if (key == GENISIS_KEY_UP || key == GENISIS_KEY_DOWN)
        {
            unsigned n = genisis_ui_items(page);
            selected = (selected + (key == GENISIS_KEY_UP ? n - 1 : 1)) % n;
            continue;
        }
        if (key == GENISIS_KEY_F5)
        {
#ifdef GENISIS_PMOD_DRIVERS
            pmod_refresh(p);
#endif
            continue;
        }
        if (key == GENISIS_KEY_F1)
        {
            genisis_ui_help();
            genisis_hal_puts("PRESS A MENU KEY TO RETURN\r\n");
            (void)wait_key(p);
            continue;
        }
        if (key == '0' || key == 27 || key == GENISIS_KEY_F10)
            return;
        unsigned action = key == '\r' || key == '\n' ? genisis_ui_action(page, selected)
                          : key >= '1' && key <= '6' ? (unsigned)(key - '0')
                          : key == 'R'               ? 2
                          : key == 'I'               ? 3
                                                     : 0;
        if (action == 1)
            return;
        if (action == 2)
        {
            genisis_ui_dialog(GENISIS_UI_TESTS, "Full memory diagnostic",
                              "Destroys loaded image.\nENTER or 1: Run\nESC: Cancel");
            genisis_hal_puts("FULL RAM TEST CONFIRM / ENTER OR 1 RUN / ESC CANCEL\r\n");
            int confirm = wait_key(p);
            if (confirm != '\r' && confirm != '\n' && confirm != '1')
                continue;
            ram_diagnostic(p);
        }
        else if (action == 3)
        {
            genisis_ui_dialog(GENISIS_UI_CPU, "Processor information",
                              "Read-only CPUINFO.\nPress a key to return.");
            cpu_info(p);
        }
        else if (action == 4)
        {
            genisis_ui_dialog(GENISIS_UI_DEVICES, "Hardware information",
                              "Controllers/devices.\nNo HDMI hot-plug.\nPress a key to return.");
#ifdef GENISIS_PMOD_DRIVERS
            pmod_refresh(p);
#endif
            platform_info(p);
            keyboard_info(p);
#ifdef GENISIS_PMOD_DRIVERS
            if (p && (p->integrated & GENISIS_PMOD))
                pmod_info();
#endif
        }
#ifdef GENISIS_PMOD_DRIVERS
        else if (action == 5)
        {
            genisis_ui_dialog(GENISIS_UI_TESTS, "Network diagnostic",
                              "Temporary DHCP test.\nNo boot-time DHCP.");
            genisis_network_test(p, &nic);
        }
        else if (action == 6)
        {
            genisis_ui_dialog(
                GENISIS_UI_MAIN, "RTC date and time",
                "UTC / 24h.\nENTER accepts a field.\nESC/F10 cancels.\n1 saves to RTC.");
            genisis_video_text(
                3, 35, "Enter: Accept field  Backspace: Edit  1: Save RTC  ESC/F10: Cancel", 0x1f);
            if (!genisis_rtc_setup(p, &rtc))
                continue;
        }
#endif
        else if (action == 7)
        {
            genisis_ui_dialog(GENISIS_UI_BOOT, "TF boot target",
                              "Read-only FAT32.\nLoading boot image.\nCRC before jump.");
            if (load_tf_image(p))
                enter_kernel();
        }
        else
        {
            genisis_hal_puts("UNKNOWN OPTION\r\n");
            continue;
        }
        genisis_hal_puts("PRESS A MENU KEY TO RETURN\r\n");
        if (wait_key(p) == GENISIS_KEY_F10)
            return;
    }
}
#endif

/* UART fica disponível antes de SDRAM init. O primeiro store externo espera
 * pelo controlador e prova disponibilidade sem depender de RAM não inicializada. */
int main(void)
{
    genisis_info.magic = GENISIS_INFO_MAGIC;
    genisis_info.version = GENISIS_VERSION;
    genisis_info.size = sizeof genisis_info;
    /* The bootstrap UART is a board contract available before enumeration.
     * Even a corrupt table must leave diagnostics in BRAM available. */
    genisis_info.uart_base = GENISIS_UART_BASE;
    genisis_info.uart_baud = 115200u;
    stage(1, "GENISIS BRAM\r\n");
    const struct genisis_platform *platform = genisis_hal_platform();
#ifdef GENISIS_BOARD_IO
    int video_ok = platform && (platform->integrated & GENISIS_VIDEO) &&
                   genisis_video_start(platform->video_base);
    post_screen(platform, 0);
    genisis_hal_puts("GENISIS R32 - PLATFORM POST\r\n");
    genisis_hal_puts(video_ok ? "VIDEO 800X600 60HZ - OUTPUT READY\r\n"
                              : "VIDEO UNAVAILABLE - UART CONSOLE ACTIVE\r\n");
    genisis_hal_puts("MONITOR DETECTION: HPD/DDC PADS NOT CONNECTED\r\n");
    cpu_info(platform);
    platform_info(platform);
#endif
    if (platform)
    {
        genisis_info.memory_base = (uint32_t)platform->memory_base;
        genisis_info.memory_bytes = platform->memory_bytes;
        genisis_info.uart_base = platform->uart_base;
        genisis_info.uart_baud = platform->uart_baud;
    }
#ifdef GENISIS_BOARD_IO
    struct genisis_post_options options = {0, post_progress};
    genisis_hal_puts("POST: QUICK RAM DATA/ADDRESS CHECK / FULL TEST OPTIONAL\r\n");
    post_ok = (unsigned)genisis_post_run_ex(platform, &genisis_post, &options);
#else
    post_ok = (unsigned)genisis_post_run(platform, &genisis_post);
#endif
#ifdef GENISIS_BOARD_IO
    if (video_ok)
        genisis_post.passed |= GENISIS_VIDEO;
#endif
    genisis_hal_puts(platform ? "GENISIS ENUM OK\r\n" : "GENISIS ENUM FAIL\r\n");
    genisis_hal_puts("GENISIS HW integrated=");
    hex(platform ? platform->integrated : 0);
    genisis_hal_puts(" verified=");
    hex(genisis_post.passed);
    genisis_hal_puts("\r\n");
    if (post_ok)
    {
        stage(2, "GENISIS SDRAM\r\n");
        genisis_hal_puts("GENISIS POST OK\r\n");
#ifdef GENISIS_BOARD_IO
        genisis_hal_puts("RAM QUICK CHECK OK: ");
        decimal(platform->memory_bytes / 1024u);
        genisis_hal_puts(" KiB ADDRESS RANGE / DATA AND ADDRESS PROBES\r\n");
        genisis_hal_puts("FULL RAM TEST AVAILABLE IN SETUP (8)\r\n");
        if (platform->core_count > 1 && (platform->integrated & GENISIS_SMP))
        {
            if (genisis_hal_read32(platform->smp_base) == 0x31504d53u &&
                genisis_hal_read32(platform->smp_base + 8u) == 2u)
                genisis_post.passed |= GENISIS_SMP;
            genisis_hal_puts("SMP: 2 CORES / SECONDARY PARKED / IPI 33\r\n");
        }
        if (platform->integrated & GENISIS_KEYBOARD)
        {
            unsigned kbd_ok = genisis_hal_read32(platform->keyboard_base) == 0x3144424bu &&
                              genisis_hal_read32(platform->keyboard_base + 28u) == 12000000u &&
                              (genisis_hal_read32(platform->keyboard_base + 4u) & 1u);
            if (kbd_ok)
                genisis_post.passed |= GENISIS_KEYBOARD;
            keyboard_info(platform);
        }
        if (platform->integrated & GENISIS_SPI)
        {
            unsigned spi_ok = genisis_hal_read32(platform->spi_base + 16u) == platform->clock_hz;
            if (spi_ok)
                genisis_post.passed |= GENISIS_SPI;
            genisis_hal_puts(spi_ok ? "TF CONTROLLER OK - IDENTIFYING CARD\r\n"
                                    : "TF CONTROLLER ERROR\r\n");
            if (spi_ok)
            {
                (void)genisis_sd_identify(platform->spi_base, &sd_card);
                if (sd_card.status == GENISIS_SD_READY)
                {
                    if ((genisis_hal_read32(platform->spi_base + GENISIS_SPI_STATUS) &
                         GENISIS_SPI_CAP_RX_BLOCK) &&
                        genisis_hal_read32(platform->spi_base + GENISIS_SPI_RX_BLOCK) ==
                            GENISIS_SPI_RX_MAGIC)
                        genisis_hal_puts("TF SPI BLOCK FIFO: ACTIVE / HW CRC16\r\n");
                    genisis_hal_puts(sd_card.high_capacity ? "TF SDHC/SDXC READY - MIB="
                                                           : "TF SDSC READY - MIB=");
                    hex(sd_card.capacity_mib);
                    genisis_hal_puts(" BLOCKS=");
                    hex(sd_card.blocks);
                    genisis_hal_puts("\r\n");
                    genisis_hal_puts(sd_card.mbr_signature
                                         ? "TF SECTOR 0 CRC OK - MBR SIGNATURE PRESENT\r\n"
                                         : "TF SECTOR 0 CRC OK - NO MBR SIGNATURE\r\n");
                    genisis_hal_puts("TF CAPACITY: ");
                    decimal(sd_card.capacity_mib);
                    genisis_hal_puts(" MiB / ");
                    decimal(sd_card.blocks);
                    genisis_hal_puts(" BLOCKS OF 512 BYTES\r\n");
                }
                else if (sd_card.status == GENISIS_SD_ABSENT)
                    genisis_hal_puts("TF CARD NOT INSERTED\r\n");
                else
                {
                    genisis_hal_puts("TF CARD ERROR ");
                    hex(sd_card.status);
                    genisis_hal_puts("\r\n");
                }
            }
        }
#ifdef GENISIS_PMOD_DRIVERS
        pmod_probe(platform);
#endif
        genisis_hal_puts("BOOT TARGET: TF FAT32 " GENISIS_TF_BOOT_PATH "\r\n");
        genisis_hal_puts("MONITOR: 8 SETUP / R FULL RAM / I CPU / ? STATUS / V VIDEO\r\n");
        genisis_hal_puts("UART DEBUG: L LOAD IMAGE / G RUN LOADED IMAGE\r\n");
#endif
    }
    else
    {
        genisis_hal_puts("GENISIS POST FAIL ");
        hex(genisis_post.error);
        genisis_hal_puts(" address=");
        hex((uint32_t)genisis_post.address);
        genisis_hal_puts(" expected=");
        hex(genisis_post.expected);
        genisis_hal_puts(" actual=");
        hex(genisis_post.actual);
        genisis_hal_puts("\r\n");
        failure(6); /* Wait for commands in the BRAM monitor. */
    }
#ifdef GENISIS_BOARD_IO
    post_screen(platform, 1);
    int pending = post_ok ? setup_window(platform, video_ok) : -1;
    if (post_ok && pending < 0 && load_tf_image(platform))
        enter_kernel();
#endif
    for (;;)
    {
        genisis_hal_puts("GENISIS READY\r\n");
#ifdef GENISIS_BOARD_IO
        int command = pending >= 0 ? pending : wait_key(platform);
        pending = -1;
#else
        int command = get_byte(0);
#endif
        if (command == '?')
            info();
#ifdef GENISIS_BOARD_IO
        else if (command == '8' || command == 127 || command == GENISIS_KEY_F1 || command == 27)
        {
            setup_menu(platform, command == 27 ? GENISIS_UI_BOOT : GENISIS_UI_MAIN);
            post_screen(platform, 1);
        }
        else if (command == 'R')
        {
            genisis_ui_dialog(
                GENISIS_UI_TESTS, "Full memory diagnostic",
                "Two patterns across\nthe entire RAM.\n\nA UART-loaded image\nis invalidated first.");
            ram_diagnostic(platform);
        }
        else if (command == 'B' && post_ok)
        {
            if (load_tf_image(platform))
                enter_kernel();
        }
        else if (command == '4')
            keyboard_info(platform);
#ifdef GENISIS_PMOD_DRIVERS
        else if (command == 'N')
            genisis_network_test(platform, &nic);
        else if (command == 'T')
            genisis_rtc_set_uart(platform, &rtc);
#endif
        else if (command == 'I')
        {
            /* Information is a separate page: retain the UART history while
             * avoiding a slow full-screen scroll for every new detail line. */
            genisis_ui_dialog(GENISIS_UI_CPU, "Processor and platform information",
                              "Read-only CPUINFO\nand platform details.\n\n8: Setup menu");
            cpu_info(platform);
            platform_info(platform);
            genisis_hal_puts("MONITOR: ? STATUS / V VIDEO / L LOAD / G RUN\r\n");
        }
        else if (command == 'V' && platform && (platform->integrated & GENISIS_VIDEO))
        {
            genisis_hal_puts("GENISIS VIDEO status=");
            hex(genisis_hal_read32(platform->video_base + 4u));
            genisis_hal_puts(" frames=");
            hex(genisis_hal_read32(platform->video_base + 20u));
            genisis_hal_puts("\r\n");
        }
#endif
        else if (command == 'L')
        {
            if (post_ok)
                load_image();
            else
                failure(6);
        }
        else if (command == 'G')
        {
            if (!post_ok)
                failure(6);
            else if (loaded)
                enter_kernel();
            else
                failure(1);
        }
        else
            failure(5);
    }
}
