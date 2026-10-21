#define GENISIS_IMAGE_TEST
#include "../tools/genisis.cpp"

static void put(Bytes &bytes, size_t offset, uint32_t value)
{
    for (unsigned i = 0; i < 4; ++i)
        bytes.at(offset + i) = uint8_t(value >> (i * 8));
}

static Bytes fixture()
{
    Bytes elf(136);
    put(elf, 0, 0x464c457f);
    put(elf, 4, 0x00010101);
    put(elf, 16, 0xfe330002);
    put(elf, 20, 1);
    put(elf, 28, 52);
    put(elf, 36, 1);
    put(elf, 40, 0x00200034);
    put(elf, 44, 2);
    put(elf, 52, 1);
    put(elf, 56, 128);
    put(elf, 68, 4);
    put(elf, 72, 8);
    put(elf, 84, 1);
    put(elf, 88, 132);
    put(elf, 92, 0x13f00000);
    put(elf, 100, 4);
    put(elf, 104, 4);
    put(elf, 128, 0x12345678);
    put(elf, 132, 0xabcdef01);
    return elf;
}

static void rejects(const Bytes &elf)
{
    bool rejected = false;
    try
    {
        image(elf);
    }
    catch (const std::runtime_error &)
    {
        rejected = true;
    }
    require(rejected, "Invalid image accepted");
}

int main()
{
    Image valid = image(fixture());
    require(valid.bram.size() == 32768 && word(valid.bram, 0) == 0x12345678 &&
                word(valid.bram, 4) == 0 && word(valid.gui, 0) == 0xabcdef01,
            "Incorrect firmware layout");
    require(crc32(Bytes{'1', '2', '3', '4', '5', '6', '7', '8', '9'}) == 0xcbf43926,
            "Incorrect CRC32");
    require(longcalls("\tjal r1,target\nlabel:\n\tjal r0,tail\n\tjalr r1,r5,0\n") ==
                "\tla r5,target\n\tjalr r1,r5,0\nlabel:\n\tjal r0,tail\n\tjalr r1,r5,0\n",
            "Incorrect call expansion");
    for (size_t size : {0u, 51u, 80u, 135u})
    {
        Bytes truncated = fixture();
        truncated.resize(size);
        rejects(truncated);
    }
    for (auto mutation : std::vector<std::pair<size_t, uint32_t>>{{4, 0x00010201},
                                                                  {16, 0x003e0002},
                                                                  {24, 4},
                                                                  {36, 0},
                                                                  {40, 0},
                                                                  {28, 0xfffffff0},
                                                                  {44, 0xffff},
                                                                  {56, 0xfffffffe},
                                                                  {60, 0x5ffc},
                                                                  {68, 9},
                                                                  {92, 0x13e00000},
                                                                  {100, 3},
                                                                  {104, 8},
                                                                  {84, 0},
                                                                  {52, 0}})
    {
        Bytes bad = fixture();
        put(bad, mutation.first, mutation.second);
        rejects(bad);
    }
    Bytes overlap = fixture();
    put(overlap, 92, 4);
    rejects(overlap);
    std::cout << "PASS_GENISIS_IMAGE_VALIDATION\n";
}
