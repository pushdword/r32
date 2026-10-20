volatile unsigned seed = 31;

__attribute__((noinline)) unsigned f(unsigned n)
{
    _Alignas(64) volatile unsigned v[5];
    v[0] = n;
    v[4] = n + 1;
    return (((unsigned long)v) & 63) ? 0 : v[0] + v[4];
}

int test_main(void)
{
    return f(seed) != 63;
}
