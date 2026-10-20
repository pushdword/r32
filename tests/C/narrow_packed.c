struct __attribute__((packed)) S
{
    unsigned char a;
    unsigned b;
    short c;
};
volatile struct S s = {0x82, 0xdeadbeef, -123};

int test_main(void)
{
    if (s.a != 0x82)
        return 1;
    if (s.b != 0xdeadbeef)
        return 2;
    if (s.c != -123)
        return 3;
    s.b = 0x12345678;
    return s.b != 0x12345678;
}
