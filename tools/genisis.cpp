#include <algorithm>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

using Bytes = std::vector<uint8_t>;

static void require(bool condition, const char *message)
{
    if (!condition)
        throw std::runtime_error(message);
}

static Bytes read(const std::string &path)
{
    std::ifstream input(path, std::ios::binary);
    require(bool(input), "Cannot open input");
    return Bytes(std::istreambuf_iterator<char>(input), {});
}

static void write(const std::string &path, const Bytes &data)
{
    std::ofstream output(path, std::ios::binary);
    require(bool(output), "Cannot open output");
    output.write(reinterpret_cast<const char *>(data.data()), data.size());
    require(bool(output), "Cannot write output");
}

static uint32_t word(const Bytes &data, size_t offset)
{
    require(offset <= data.size() && data.size() - offset >= 4, "Truncated ELF field");
    return uint32_t(data[offset]) | uint32_t(data[offset + 1]) << 8 |
           uint32_t(data[offset + 2]) << 16 | uint32_t(data[offset + 3]) << 24;
}

static void append(Bytes &data, uint32_t value)
{
    for (unsigned i = 0; i < 4; ++i)
        data.push_back(uint8_t(value >> (8 * i)));
}

static uint32_t crc32(const Bytes &data)
{
    uint32_t crc = ~0u;
    for (uint8_t byte : data)
    {
        crc ^= byte;
        for (unsigned bit = 0; bit < 8; ++bit)
            crc = (crc >> 1) ^ ((0u - (crc & 1u)) & 0xedb88320u);
    }
    return ~crc;
}

struct Image
{
    Bytes bram = Bytes(32768);
    Bytes gui;
};

static Image image(const Bytes &elf)
{
    require(elf.size() >= 52 && word(elf, 0) == 0x464c457fu && elf[4] == 1 && elf[5] == 1 &&
                elf[6] == 1,
            "Expected ELF32 little-endian image");
    require(word(elf, 16) == 0xfe330002u && word(elf, 20) == 1 && word(elf, 24) == 0 &&
                word(elf, 36) == 1,
            "Invalid R32 firmware ABI or entry");
    require((word(elf, 40) & 65535u) == 52 && (word(elf, 40) >> 16) == 32,
            "Invalid ELF header sizes");
    size_t count = word(elf, 44) & 65535u;
    size_t table = word(elf, 28);
    require(table <= elf.size() && count <= (elf.size() - table) / 32, "Truncated program headers");
    Image result;
    Bytes used(32768);
    bool resident = false;
    for (size_t i = 0; i < count; ++i)
    {
        size_t header = table + i * 32;
        if (word(elf, header) != 1)
            continue;
        size_t offset = word(elf, header + 4);
        uint32_t address = word(elf, header + 8);
        uint32_t files = word(elf, header + 16);
        uint32_t memory = word(elf, header + 20);
        require(files <= memory && offset <= elf.size() && files <= elf.size() - offset,
                "Invalid segment bounds");
        if (address < 32768)
        {
            require(address <= 0x6000 && memory <= 0x6000 - address,
                    "Resident image exceeds BRAM stack boundary");
            for (size_t n = 0; n < memory; ++n)
            {
                require(!used[address + n], "Overlapping resident segments");
                used[address + n] = 1;
            }
            std::copy(elf.begin() + offset, elf.begin() + offset + files,
                      result.bram.begin() + address);
            resident = true;
        }
        else
        {
            require(address == 0x13f00000 && result.gui.empty() && files == memory && files &&
                        files <= 0x80000 && files % 4 == 0,
                    "Invalid GUI segment");
            result.gui.assign(elf.begin() + offset, elf.begin() + offset + files);
        }
    }
    require(resident && !result.gui.empty(), "Missing resident or GUI segment");
    return result;
}

static std::string longcalls(const std::string &assembly)
{
    const std::regex direct("[ \\t]*jal r1,([^ \\t#\\r]+)[ \\t\\r]*");
    std::istringstream input(assembly);
    std::ostringstream output;
    std::string line;
    while (std::getline(input, line))
    {
        std::smatch match;
        if (std::regex_match(line, match, direct))
            output << "\tla r5," << match[1].str() << "\n\tjalr r1,r5,0\n";
        else
            output << line << '\n';
    }
    return output.str();
}

#ifndef GENISIS_IMAGE_TEST
int main(int argc, char **argv)
{
    try
    {
        require(argc >= 2, "Expected longcalls or image command");
        std::string command = argv[1];
        if (command == "longcalls")
        {
            require(argc == 4, "Usage: genisis longcalls input.s output.s");
            Bytes input = read(argv[2]);
            std::string text = longcalls(std::string(input.begin(), input.end()));
            write(argv[3], Bytes(text.begin(), text.end()));
        }
        else
        {
            require(command == "image" && argc == 6,
                    "Usage: genisis image input.elf bram.bin firmware.hex genisis.r32");
            Image parts = image(read(argv[2]));
            write(argv[3], parts.bram);
            std::ostringstream hex;
            hex << std::hex << std::setfill('0');
            for (size_t offset = 0; offset < parts.bram.size(); offset += 4)
                hex << std::setw(8) << word(parts.bram, offset) << '\n';
            std::string text = hex.str();
            write(argv[4], Bytes(text.begin(), text.end()));
            Bytes package;
            for (uint32_t value : {0x4b323352u, 1u, 0x13f00000u, uint32_t(parts.gui.size()),
                                   uint32_t(parts.gui.size()), 0x13f00000u, crc32(parts.gui), 0u})
                append(package, value);
            package.insert(package.end(), parts.gui.begin(), parts.gui.end());
            write(argv[5], package);
        }
        return 0;
    }
    catch (const std::exception &error)
    {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
#endif
