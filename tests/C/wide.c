typedef unsigned long long u64;
volatile u64 a = 0x123456789abcdef0ull, b = 0xfedcba9876543210ull;
volatile unsigned shifts[7] = {0, 1, 15, 31, 32, 33, 63};

int test_main(void)
{
    u64 x = a, y = b;
    if (x + y != 0x1111111111111100ull)
        return 1;
    if (x * y != 0x236d88fe5618cf00ull)
        return 2;
    for (unsigned i = 0; i < 7; i++)
    {
        unsigned n = shifts[i];
        u64 z = x << n;
        if (n && ((z >> n) != (x & (~0ull >> n))))
            return 3;
    }
    if (!(x < y))
        return 4;
    return 0;
}
