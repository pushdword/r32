volatile unsigned value = 17;

int test_main(void)
{
    unsigned old = __atomic_fetch_add(&value, 5, __ATOMIC_SEQ_CST);
    if (old != 17 || value != 22)
        return 1;
    unsigned expected = 22;
    if (!__atomic_compare_exchange_n(&value, &expected, 99, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST))
        return 2;
    expected = 11;
    if (__atomic_compare_exchange_n(&value, &expected, 88, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST))
        return 3;
    return value != 99 || expected != 99;
}
