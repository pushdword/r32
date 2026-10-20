static volatile unsigned source;

static unsigned pop(unsigned x)
{
    unsigned n = 0;
    while (x)
    {
        n += x & 1;
        x >>= 1;
    }
    return n;
}

int test_main(void)
{
    for (unsigned i = 0; i < 32; i++)
    {
        source = 1u << i;
        unsigned x = source;
        if (__builtin_ctz(x) != (int)i || __builtin_clz(x) != (int)(31 - i) ||
            __builtin_popcount(x) != 1)
            return 1;
    }
    for (unsigned i = 0; i < 64; i++)
    {
        source = i * 0x98765431u;
        unsigned x = source;
        if (__builtin_popcount(x) != (int)pop(x))
            return 2;
    }
    return 0;
}
