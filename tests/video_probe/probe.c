#define R(a) (*(volatile unsigned *)(a))

static void put(unsigned char c)
{
    while (!(R(0xf0000004) & 1))
    {
    }
    *(volatile unsigned char *)0xf0000000 = c;
}

static void text(const char *s)
{
    while (*s)
        put(*s++);
}

static void hex(unsigned x)
{
    for (unsigned i = 32; i;)
    {
        i -= 4;
        unsigned c = x >> i & 15;
        put(c < 10 ? '0' + c : 'A' + c - 10);
    }
}

static void line(unsigned a)
{
    hex(a);
    put('=');
    hex(R(a));
    text("\r\n");
}

static void dump(void)
{
    text("R32_VIDEO_REGS\r\n");
    for (unsigned i = 0; i < 7; i++)
    {
        line(0xf0010000 + 4 * i);
    }
#if defined(R32_GUI_CONSOLE_ADDRESS)
    line(R32_GUI_CONSOLE_ADDRESS);
#endif
#if defined(R32_GUI_MIRROR_ADDRESS)
    line(R32_GUI_MIRROR_ADDRESS);
#endif
    text("R32_VIDEO_CELLS_BEGIN\r\n");
    for (unsigned i = 0; i < 3700; i++)
    {
        hex(R(0xf0010100 + 4 * i));
        put(i % 100 == 99 ? '\n' : ' ');
    }
    text("\r\nR32_VIDEO_CELLS_END\r\n");
}

static void pattern(void)
{
    for (unsigned i = 0; i < 3700; i++)
        R(0xf0010100 + 4 * i) = 0x7020;
    const char *s = "R32 HDMI DIRECT TEST";
    for (unsigned i = 0; s[i]; i++)
        R(0xf0010100 + 4 * (35 + i)) = 0x1f00 | (unsigned char)s[i];
    R(0xf0010010) = 1;
    text("R32_VIDEO_DIRECT_PATTERN_WRITTEN\r\n");
}

int main(void)
{
    text("R32_VIDEO_PROBE_BEGIN\r\n");
    dump();
    text("R32_VIDEO_PROBE_READY\r\n");
    for (;;)
    {
        while (!(R(0xf0000004) & 2))
        {
        }
        unsigned c = R(0xf0000000) & 255;
        if (c == 'p')
            pattern();
        else if (c == 'v')
            dump();
        else if (c == 'b')
        {
            __asm__ volatile("li r5,0\njalr r0,r5,0" ::: "memory");
        }
    }
}
