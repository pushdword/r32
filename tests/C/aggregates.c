struct S
{
    unsigned a, b, c;
};

volatile unsigned seed = 17;

__attribute__((noinline)) struct S make(unsigned x)
{
    struct S s = {x, x + 1, x + 2};
    return s;
}

__attribute__((noinline)) unsigned sum(struct S s)
{
    return s.a + s.b + s.c;
}

int test_main(void)
{
    struct S s = make(seed);
    return sum(s) != 54;
}
