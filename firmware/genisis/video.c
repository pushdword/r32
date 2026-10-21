/* Firmware writes only the text MMIO window. Scanout/font/TMDS live in RTL,
 * independent of SDRAM. UART remains the mandatory bootstrap/fallback path. */
#include "video.h"
#include "hal.h"
static uintptr_t console;
static unsigned row, column, left, top, width = 100, height = 37;
static unsigned char attribute = 0x0f;
static int mirrored = 1;

static void cell(unsigned index, uint32_t value)
{
    genisis_hal_write32(console + 256u + index * 4u, value);
}

void genisis_video_clear(void)
{
    row = column = 0;
    left = top = 0;
    width = 100;
    height = 37;
    attribute = 0x0f;
    mirrored = 1;
    if (console)
        for (unsigned i = 0; i < 3700; ++i)
            cell(i, 0x0f20); /* White on black. */
}

void genisis_video_mirror(int enabled)
{
    mirrored = enabled;
}

void genisis_video_fill(unsigned x, unsigned y, unsigned w, unsigned h, unsigned char glyph,
                        unsigned char attr)
{
    if (!console || x >= 100 || y >= 37)
        return;
    if (w > 100 - x)
        w = 100 - x;
    if (h > 37 - y)
        h = 37 - y;
    for (unsigned r = y; r < y + h; ++r)
        for (unsigned c = x; c < x + w; ++c)
            cell(r * 100 + c, ((uint32_t)attr << 8) | glyph);
}

void genisis_video_text(unsigned x, unsigned y, const char *text, unsigned char attr)
{
    if (!console || x >= 100 || y >= 37)
        return;
    while (*text && x < 100)
        cell(y * 100 + x++, ((uint32_t)attr << 8) | (unsigned char)*text++);
}

void genisis_video_console(unsigned x, unsigned y, unsigned w, unsigned h, unsigned char attr)
{
    if (x >= 100 || y >= 37 || !w || !h)
        return;
    left = x;
    top = y;
    width = w < 100 - x ? w : 100 - x;
    height = h < 37 - y ? h : 37 - y;
    attribute = attr;
    row = column = 0;
    mirrored = 1;
}

int genisis_video_start(uintptr_t base)
{
    console = 0;
    row = column = 0;
    if (!base || genisis_hal_read32(base) != 0x31545854u ||
        genisis_hal_read32(base + 8u) != 0x00250064u ||
        genisis_hal_read32(base + 12u) != 0x02580320u)
        return 0;
    console = base;
    genisis_video_clear();
    genisis_hal_write32(base + 16u, 1);
    /* A missing PLL lock never prevents the serial POST/monitor. */
    unsigned budget = 100000;
    while (!(genisis_hal_read32(base + 4u) & 1u))
        if (!--budget)
        {
            console = 0;
            return 0;
        }
    return 1;
}

void genisis_video_putc(unsigned char byte)
{
    if (!console || !mirrored)
        return;
    if (byte == '\b')
    {
        if (column)
            --column;
        return;
    } /* BIOS field editing: backspace/space/backspace. */
    if (byte == '\r')
    {
        column = 0;
        return;
    }
    if (byte == '\n')
    {
        column = 0;
        ++row;
    }
    else if (byte >= 32 && byte < 127)
    {
        cell((top + row) * 100u + left + column, ((uint32_t)attribute << 8) | byte);
        if (++column == width)
        {
            column = 0;
            ++row;
        }
    }
    /* Protocol ACK and non-text bytes must not become visible glyphs. */
    if (row < height)
        return;
    for (unsigned r = 0; r + 1 < height; ++r)
        for (unsigned c = 0; c < width; ++c)
        {
            unsigned index = (top + r) * 100u + left + c;
            cell(index, genisis_hal_read32(console + 256u + (index + 100u) * 4u));
        }
    genisis_video_fill(left, top + height - 1, width, 1, ' ', attribute);
    row = height - 1;
}
