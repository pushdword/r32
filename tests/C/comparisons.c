volatile int seed = -1234567;

__attribute__((noinline)) int cmp(int x, int y)
{
    return (x < y) + 2 * (x >= y) + 4 * (x == y) + 8 * (x != y) + 16 * (x <= y) + 32 * (x > y) +
           64 * ((unsigned)x < (unsigned)y) + 128 * ((unsigned)x >= (unsigned)y);
}

int test_main(void)
{
    int x = seed;
    if (cmp(x, 7) != 153)
        return 1;
    if (cmp(x, x) != 150)
        return 2;
    if (cmp(7, x) != 106)
        return 3;
    return 0;
}
