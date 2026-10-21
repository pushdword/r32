/* Text-cell BIOS panels for hardware status, POST results and setup actions. */
#include "ui.h"
#include "video.h"
#include "description.h"

enum
{
    NORMAL = 0x70,
    BLUE = 0x1f,
    INK = 0x71,
    POST = 0x0f
};

static int post_view;
static char text[80];
static unsigned used;

static void start(const char *s)
{
    used = 0;
    while (*s && used < 79)
        text[used++] = *s++;
    text[used] = 0;
}

static void add(const char *s)
{
    while (*s && used < 79)
        text[used++] = *s++;
    text[used] = 0;
}

static void number(uint32_t v)
{
    char digits[10];
    unsigned n = 0;
    do
    {
        digits[n++] = (char)('0' + v % 10);
        v /= 10;
    } while (v);
    while (n && used < 79)
        text[used++] = digits[--n];
    text[used] = 0;
}

static void pair(unsigned v)
{
    if (v < 10)
        add("0");
    number(v);
}

static void date(const struct genisis_rtc *r)
{
    if (!r || (r->status != GENISIS_RTC_READY && r->status != GENISIS_RTC_UNSET))
    {
        add("Not available");
        return;
    }
    number(r->year);
    add("-");
    pair(r->month);
    add("-");
    pair(r->day);
    add("  ");
    pair(r->hour);
    add(":");
    pair(r->minute);
    add(":");
    pair(r->second);
    add(r->osf ? " UTC [unset]" : " UTC");
}

static void icon(unsigned x, unsigned y, unsigned char attr)
{
    /* Glyphs10..17 are eight tiles of the 32x32 one-bit emblem. No image
     * decoder or extra BRAM: they occupy formerly blank font slots. */
    for (unsigned r = 0; r < 2; ++r)
        for (unsigned c = 0; c < 4; ++c)
            genisis_video_fill(x + c, y + r, 1, 1, (unsigned char)(0x10 + r * 4 + c), attr);
}

static void box(unsigned x, unsigned y, unsigned w, unsigned h)
{
    genisis_video_fill(x, y, w, 1, '-', INK);
    genisis_video_fill(x, y + h - 1, w, 1, '-', INK);
    genisis_video_fill(x, y, 1, h, '|', INK);
    genisis_video_fill(x + w - 1, y, 1, h, '|', INK);
    genisis_video_fill(x, y, 1, 1, '+', INK);
    genisis_video_fill(x + w - 1, y, 1, 1, '+', INK);
    genisis_video_fill(x, y + h - 1, 1, 1, '+', INK);
    genisis_video_fill(x + w - 1, y + h - 1, 1, 1, '+', INK);
}

static const char *const tabs[] = {"Main", "CPU", "Devices", "Tests", "Boot", "Exit"};

static void frame(unsigned page, const char *title, const char *help)
{
    post_view = 0;
    genisis_video_clear();
    genisis_video_mirror(0);
    genisis_video_fill(0, 0, 100, 37, ' ', NORMAL);
    genisis_video_fill(0, 0, 100, 3, ' ', BLUE);
    genisis_video_text(35, 0, "GENISIS BIOS SETUP UTILITY", BLUE);
    genisis_video_text(3, 1, "R32 platform firmware", BLUE);
    for (unsigned i = 0; i < GENISIS_UI_PAGES; ++i)
    {
        unsigned x = 3 + i * 16;
        unsigned char a = i == page ? INK : BLUE;
        genisis_video_fill(x, 2, 14, 1, ' ', a);
        genisis_video_text(x + 1, 2, tabs[i], a);
    }
    box(1, 4, 98, 29);
    genisis_video_fill(70, 5, 1, 27, '|', INK);
    genisis_video_text(4, 5, title, INK);
    genisis_video_text(73, 6, "Item help", INK);
    /* Help has explicit line breaks, bounded to its 24-column panel. */
    unsigned x = 73, y = 8;
    while (*help && y < 27)
    {
        if (*help == '\n')
        {
            x = 73;
            ++y;
            ++help;
            continue;
        }
        if (x < 97)
            genisis_video_fill(x++, y, 1, 1, (unsigned char)*help, INK);
        ++help;
    }
    genisis_video_fill(0, 34, 100, 3, ' ', BLUE);
    genisis_video_text(3, 34, "Left/Right: Page   Up/Down: Select   Enter: Open   ESC: Back", BLUE);
    genisis_video_text(3, 35, "F1: Help   F5: Refresh   F10: Return to POST   UART: 1..6 shortcuts",
                       BLUE);
    icon(94, 34, BLUE);
}

static void item(unsigned row, const char *label, const char *value, int selected)
{
    unsigned char a = selected ? BLUE : NORMAL;
    genisis_video_fill(4, row, 64, 1, ' ', a);
    genisis_video_text(5, row, label, a);
    genisis_video_text(33, row, value, a);
    if (selected)
        genisis_video_text(4, row, ">", a);
}

unsigned genisis_ui_items(unsigned p)
{
    static const unsigned char counts[] = {4, 1, 2, 2, 2, 1};
    return p < 6 ? counts[p] : 1;
}

unsigned genisis_ui_action(unsigned p, unsigned i)
{
    static const unsigned char actions[6][4] = {{6, 3, 4, 1}, {3, 0, 0, 0}, {4, 4, 0, 0},
                                                {2, 5, 0, 0}, {7, 1, 0, 0}, {1, 0, 0, 0}};
    return p < 6 && i < genisis_ui_items(p) ? actions[p][i] : 0;
}

void genisis_ui_menu(const struct genisis_ui_state *s, unsigned p, unsigned selected)
{
    const struct genisis_platform *b = s->platform;
    const struct genisis_cpu_description *cpu = genisis_hal_cpu_description();
    static const char *const help[] = {
        "View platform details.\n\nRTC uses UTC / 24h.\nOnly explicit Save\nwrites the clock.",
        "Read-only CPUINFO.\n\nIdentity and features\ncome from hardware.",
        "F5 refreshes RTC/link.\n\nControllers and devices\nare listed separately.\nNo HDMI hot-plug.",
        "Tests are optional.\n\nFull RAM destroys a\nUART-loaded image.\nDHCP is temporary.",
        "Read-only FAT32.\n" GENISIS_TF_BOOT_PATH "\n\nCRC checked before\nstarting the image.",
        "Return to POST/UART.\n\nSaved RTC time remains\nstored in the clock."};
    static const char *const labels[6][4] = {
        {"System date/time", "Processor", "Platform", "Continue"},
        {"Processor information", 0, 0, 0},
        {"Detected devices", "Refresh status", 0, 0},
        {"Full RAM test", "Network DHCP test", 0, 0},
        {"TF boot image", "UART debug console", 0, 0},
        {"Exit setup", 0, 0, 0}};
    static const char *const values[6][4] = {
        {"", "", "", "Return to POST"},
        {"", 0, 0, 0},
        {"Open hardware details", "RTC / Ethernet link", 0, 0},
        {"2 patterns / optional", "Temporary lease / diagnostic", 0, 0},
        {GENISIS_TF_BOOT_PATH, "Return for L / G", 0, 0},
        {"Return to POST", 0, 0, 0}};
    if (p >= 6)
        p = 0;
    frame(p, tabs[p], help[p]);
    for (unsigned i = 0; i < genisis_ui_items(p); ++i)
    {
        const char *v = values[p][i];
        if (p == 0 && i == 0)
        {
            start("");
            date(s->rtc);
            v = text;
        }
        else if ((p == 0 && i == 1) || p == 1)
            v = cpu->name;
        else if (p == 0 && i == 2)
        {
            start("");
            number(b ? genisis_r32_cpu_hz() / 1000000 : 0);
            add(" MHz / ");
            number(b ? b->core_count : 0);
            add(" cores");
            v = text;
        }
        item(8 + i * 2, labels[p][i], v, selected == i);
    }
    start("Installed memory: ");
    number(b ? b->memory_bytes / 1048576 : 0);
    add(" MiB SDRAM");
    genisis_video_text(5, 20, text, NORMAL);
    genisis_video_text(5, 22, "Default RAM POST: quick data/address checks", NORMAL);
    genisis_video_mirror(0);
}

void genisis_ui_dialog(unsigned page, const char *title, const char *help)
{
    frame(page, title, help);
    genisis_video_console(4, 8, 64, 23, NORMAL);
}

void genisis_ui_help(void)
{
    genisis_ui_dialog(
        0, "Setup help",
        "ESC: Back\n\nUse arrows on USB HID\nor an ANSI terminal.\n\nNumber shortcuts\nalso work via UART.");
    genisis_hal_puts(
        "GENISIS SETUP HELP\r\nLEFT/RIGHT SELECT PAGE / UP/DOWN SELECT ITEM\r\nENTER OPEN / ESC BACK / F10 RETURN TO POST\r\nF5 REFRESH RTC AND ETHERNET LINK\r\n1 CONTINUE / 2 FULL RAM / 3 CPU / 4 HARDWARE\r\n5 MANUAL DHCP TEST / 6 RTC DATE AND TIME\r\nRTC SAVE IS EXPLICIT; NO OTHER SETTINGS ARE PERSISTED.\r\n");
}

void genisis_ui_post(const struct genisis_ui_state *s, int complete)
{
    genisis_video_clear();
    genisis_video_mirror(0);
    post_view = 1;
    icon(2, 1, 0x0b);
    genisis_video_text(8, 1, "GENISIS - R32 PLATFORM FIRMWARE", POST);
    genisis_video_text(8, 2, "Hardware POST / BIOS setup", 0x07);
    const struct genisis_platform *b = s->platform;
    const struct genisis_cpu_description *c = genisis_hal_cpu_description();
    start("Main processor: ");
    add(c->name);
    add("  ");
    number(b ? genisis_r32_cpu_hz() / 1000000 : 0);
    add(" MHz  /  ");
    number(b ? b->core_count : 0);
    add(" cores");
    genisis_video_text(2, 5, text, POST);
    start("Architecture: R32 / ");
    number(c->bits);
    add(" bit / ");
    number(c->forms);
    add(" ISA forms");
    if (c->features & R32_CPU_FPU32)
        add(" / FPU32");
    genisis_video_text(2, 6, text, POST);
    start("Memory: ");
    number(b ? b->memory_bytes / 1024 : 0);
    add(" KiB installed / SDRAM");
    genisis_video_text(2, 8, text, POST);
    genisis_video_text(2, 11, "POST mode: quick data/address checks / full test available in setup",
                       0x07);
    genisis_video_text(2, 14, "Detecting integrated controllers and external devices ...", POST);
    if (complete)
    {
        genisis_video_text(2, 9,
                           s->post && !s->post->error
                               ? "Memory quick test: OK / not a full cell scan"
                               : "Memory/CPU POST: FAILED - see UART details",
                           s->post && !s->post->error ? 0x0a : 0x0c);
        genisis_video_text(2, 16, "Timer: integrated / IRQ0", POST);
        start("TF card: ");
        if (s->card && s->card->status == GENISIS_SD_READY)
        {
            number(s->card->capacity_mib);
            add(" MiB / sector0 CRC OK");
        }
        else
            add("not ready / absent");
        genisis_video_text(2, 18, text, POST);
        unsigned k =
            b && (b->integrated & GENISIS_KEYBOARD) ? genisis_hal_read32(b->keyboard_base + 4) : 0;
        genisis_video_text(2, 20, k & 2 ? "USB keyboard: detected" : "USB keyboard: not detected",
                           POST);
        start("RTC: ");
        date(s->rtc);
        genisis_video_text(2, 22, text, POST);
        genisis_video_text(2, 24,
                           s->nic && s->nic->status == GENISIS_W5500_READY
                               ? (s->nic->link ? "Ethernet W5500: detected / link up"
                                               : "Ethernet W5500: detected / link down")
                               : "Ethernet W5500: not detected",
                           POST);
        genisis_video_text(2, 27, "Boot target: TF FAT32 " GENISIS_TF_BOOT_PATH, POST);
        genisis_video_text(2, 29,
                           s->post && !s->post->error
                               ? "POST complete. UART debug console ready."
                               : "POST failed. Firmware stays in debug console.",
                           POST);
    }
    genisis_video_text(
        2, 34, "Press 8, Delete or F1 for SETUP    ESC: Boot page    R: Full RAM test", POST);
    genisis_video_text(
        2, 35, "UART 115200 8N1  |  I: CPU info  ?: Status  L/G: Load/run debug image", 0x07);
}

void genisis_ui_progress(unsigned phase, uint32_t done, uint32_t total)
{
    if (!post_view)
        return;
    static const char *const names[] = {"CPU arithmetic",     "UART",
                                        "Memory data bus",    "Memory address bus",
                                        "RAM pattern1 write", "RAM pattern1 verify",
                                        "RAM pattern2 write", "RAM pattern2 verify",
                                        "Timer reset"};
    if (phase >= 9)
        return;
    start(names[phase]);
    add(": ");
    number(done);
    add(" / ");
    number(total);
    add(done == total ? "  OK" : "  testing");
    genisis_video_fill(2, 9, 85, 1, ' ', POST);
    genisis_video_text(2, 9, text, POST);
    unsigned n = total ? (done >= total ? 24 : done / (total / 24 + 1)) : 0;
    genisis_video_text(2, 10, "[", POST);
    genisis_video_fill(3, 10, 24, 1, '-', 0x07);
    genisis_video_fill(3, 10, n, 1, '#', 0x0a);
    genisis_video_text(27, 10, "]", POST);
}

/* Direct cell updates keep the POST visible and do not write UART bytes.
 * The caller reports measured byte work and throttles updates to whole percent
 * changes or phase transitions. Only READY may display 100 percent. */
const char *genisis_ui_boot_phase(unsigned phase)
{
    static const char *const names[] = {
        "Opening boot image",           "Reading image header",   "Loading image from TF",
        "Verifying image in SDRAM",     "Preparing image memory", "Ready - starting boot image",
        "Boot failed - setup available"};
    return phase <= GENISIS_BOOT_ERROR ? names[phase] : "Boot status";
}

void genisis_ui_boot_progress(unsigned phase, uint32_t done, uint32_t total, unsigned percent)
{
    unsigned char attr = phase == GENISIS_BOOT_ERROR   ? 0x0c
                         : phase == GENISIS_BOOT_READY ? 0x0a
                                                       : 0x0b;
    if (percent > 99)
        percent = phase == GENISIS_BOOT_READY ? 100 : 99;
    genisis_video_mirror(0);
    genisis_video_fill(44, 27, 44, 1, ' ', POST);
    genisis_video_text(44, 27, "[", attr);
    genisis_video_fill(45, 27, 30, 1, '-', 0x07);
    genisis_video_fill(45, 27, percent * 30 / 100, 1, '#', attr);
    genisis_video_text(75, 27, "]", attr);
    start("");
    number(percent);
    add("%");
    genisis_video_text(77, 27, text, attr);
    genisis_video_fill(2, 29, 96, 2, ' ', POST);
    genisis_video_text(2, 29, genisis_ui_boot_phase(phase), attr);
    if (total)
    {
        start("");
        number(done);
        add(" / ");
        number(total);
        add(" bytes in this phase");
        genisis_video_text(2, 30, text, 0x07);
    }
}
