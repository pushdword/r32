static volatile int a[3] = {-1, -1, -1};
static volatile unsigned char b[9] = {255, 255, 255, 255, 255, 255, 255, 255, 255};

int test_main(void)
{
    for (unsigned i = 0; i < 3; i++)
        if (a[i] != -1)
            return 1;
    for (unsigned i = 0; i < 9; i++)
        if (b[i] != 255)
            return 2;
    return 0;
}
