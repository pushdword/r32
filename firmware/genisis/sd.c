/* Require card detect before issuing SD SPI commands.
 * Initialize at divider 125 and identify the card by reading its registers
 * and sector zero. Bound polling, response, token and retry waits separately. */
#include "sd.h"
#include "hal.h"

static inline uint32_t sd_read32(uintptr_t p)
{
    return *(volatile uint32_t *)p;
}

static inline void sd_write32(uintptr_t p, uint32_t v)
{
    *(volatile uint32_t *)p = v;
}

static int transfer(uintptr_t base, unsigned char tx)
{
    sd_write32(base + 8u, tx);
    unsigned budget = 20000;
    while (sd_read32(base + 12u) & 1u)
        if (!--budget)
            return -1;
    return (int)(sd_read32(base + 8u) & 255u);
}

static void deselect(uintptr_t base)
{
    if (sd_read32(base + 12u) & 1u)
        sd_write32(base + 20u, 1); // Abort a timed-out byte before changing CS.
    sd_write32(base + 4u, 1);
    if (transfer(base, 255) < 0)
        sd_write32(base + 20u, 1);
}

static int command(uintptr_t base, unsigned cmd, uint32_t arg, unsigned crc)
{
    deselect(base);
    sd_write32(base + 4u, 0);
    if (transfer(base, 255) < 0 || transfer(base, (unsigned char)(64u | cmd)) < 0)
        return -1;
    for (unsigned shift = 32; shift;)
    {
        shift -= 8;
        if (transfer(base, (unsigned char)(arg >> shift)) < 0)
            return -1;
    }
    if (transfer(base, (unsigned char)crc) < 0)
        return -1;
    for (unsigned count = 0; count < 8; ++count)
    {
        int byte = transfer(base, 255);
        if (byte < 0 || !(byte & 128))
        {
#ifdef GENISIS_SD_TRACE
            extern void genisis_sd_trace(unsigned, uint32_t, int);
            genisis_sd_trace(cmd, arg, byte);
#endif
            return byte;
        }
    }
#ifdef GENISIS_SD_TRACE
    extern void genisis_sd_trace(unsigned, uint32_t, int);
    genisis_sd_trace(cmd, arg, -1);
#endif
    return -1;
}

static const uint16_t crc_table[256] = {
    0x0000u, 0x1021u, 0x2042u, 0x3063u, 0x4084u, 0x50a5u, 0x60c6u, 0x70e7u, 0x8108u, 0x9129u,
    0xa14au, 0xb16bu, 0xc18cu, 0xd1adu, 0xe1ceu, 0xf1efu, 0x1231u, 0x0210u, 0x3273u, 0x2252u,
    0x52b5u, 0x4294u, 0x72f7u, 0x62d6u, 0x9339u, 0x8318u, 0xb37bu, 0xa35au, 0xd3bdu, 0xc39cu,
    0xf3ffu, 0xe3deu, 0x2462u, 0x3443u, 0x0420u, 0x1401u, 0x64e6u, 0x74c7u, 0x44a4u, 0x5485u,
    0xa56au, 0xb54bu, 0x8528u, 0x9509u, 0xe5eeu, 0xf5cfu, 0xc5acu, 0xd58du, 0x3653u, 0x2672u,
    0x1611u, 0x0630u, 0x76d7u, 0x66f6u, 0x5695u, 0x46b4u, 0xb75bu, 0xa77au, 0x9719u, 0x8738u,
    0xf7dfu, 0xe7feu, 0xd79du, 0xc7bcu, 0x48c4u, 0x58e5u, 0x6886u, 0x78a7u, 0x0840u, 0x1861u,
    0x2802u, 0x3823u, 0xc9ccu, 0xd9edu, 0xe98eu, 0xf9afu, 0x8948u, 0x9969u, 0xa90au, 0xb92bu,
    0x5af5u, 0x4ad4u, 0x7ab7u, 0x6a96u, 0x1a71u, 0x0a50u, 0x3a33u, 0x2a12u, 0xdbfdu, 0xcbdcu,
    0xfbbfu, 0xeb9eu, 0x9b79u, 0x8b58u, 0xbb3bu, 0xab1au, 0x6ca6u, 0x7c87u, 0x4ce4u, 0x5cc5u,
    0x2c22u, 0x3c03u, 0x0c60u, 0x1c41u, 0xedaeu, 0xfd8fu, 0xcdecu, 0xddcdu, 0xad2au, 0xbd0bu,
    0x8d68u, 0x9d49u, 0x7e97u, 0x6eb6u, 0x5ed5u, 0x4ef4u, 0x3e13u, 0x2e32u, 0x1e51u, 0x0e70u,
    0xff9fu, 0xefbeu, 0xdfddu, 0xcffcu, 0xbf1bu, 0xaf3au, 0x9f59u, 0x8f78u, 0x9188u, 0x81a9u,
    0xb1cau, 0xa1ebu, 0xd10cu, 0xc12du, 0xf14eu, 0xe16fu, 0x1080u, 0x00a1u, 0x30c2u, 0x20e3u,
    0x5004u, 0x4025u, 0x7046u, 0x6067u, 0x83b9u, 0x9398u, 0xa3fbu, 0xb3dau, 0xc33du, 0xd31cu,
    0xe37fu, 0xf35eu, 0x02b1u, 0x1290u, 0x22f3u, 0x32d2u, 0x4235u, 0x5214u, 0x6277u, 0x7256u,
    0xb5eau, 0xa5cbu, 0x95a8u, 0x8589u, 0xf56eu, 0xe54fu, 0xd52cu, 0xc50du, 0x34e2u, 0x24c3u,
    0x14a0u, 0x0481u, 0x7466u, 0x6447u, 0x5424u, 0x4405u, 0xa7dbu, 0xb7fau, 0x8799u, 0x97b8u,
    0xe75fu, 0xf77eu, 0xc71du, 0xd73cu, 0x26d3u, 0x36f2u, 0x0691u, 0x16b0u, 0x6657u, 0x7676u,
    0x4615u, 0x5634u, 0xd94cu, 0xc96du, 0xf90eu, 0xe92fu, 0x99c8u, 0x89e9u, 0xb98au, 0xa9abu,
    0x5844u, 0x4865u, 0x7806u, 0x6827u, 0x18c0u, 0x08e1u, 0x3882u, 0x28a3u, 0xcb7du, 0xdb5cu,
    0xeb3fu, 0xfb1eu, 0x8bf9u, 0x9bd8u, 0xabbbu, 0xbb9au, 0x4a75u, 0x5a54u, 0x6a37u, 0x7a16u,
    0x0af1u, 0x1ad0u, 0x2ab3u, 0x3a92u, 0xfd2eu, 0xed0fu, 0xdd6cu, 0xcd4du, 0xbdaau, 0xad8bu,
    0x9de8u, 0x8dc9u, 0x7c26u, 0x6c07u, 0x5c64u, 0x4c45u, 0x3ca2u, 0x2c83u, 0x1ce0u, 0x0cc1u,
    0xef1fu, 0xff3eu, 0xcf5du, 0xdf7cu, 0xaf9bu, 0xbfbau, 0x8fd9u, 0x9ff8u, 0x6e17u, 0x7e36u,
    0x4e55u, 0x5e74u, 0x2e93u, 0x3eb2u, 0x0ed1u, 0x1ef0u,
};

static uint16_t crc_byte(uint16_t crc, unsigned char byte)
{
    return (uint16_t)((crc << 8) ^ crc_table[(crc >> 8) ^ byte]);
}

/* Block registers are probed only after STATUS advertises them. Legacy
 * bitstreams fault on unknown offsets24/28, so never read them speculatively. */
typedef uint32_t sd_alias_word __attribute__((__may_alias__));

static int block_error(uintptr_t base, int status)
{
    sd_write32(base + GENISIS_SPI_ABORT, 1u);
    return status;
}

static int receive_block(uintptr_t base, unsigned char *data, unsigned bytes)
{
    uint32_t status = sd_read32(base + GENISIS_SPI_STATUS);
    if ((status & GENISIS_SPI_BUSY) || GENISIS_SPI_WORDS(status) || !bytes || bytes > 512u)
        return block_error(base, GENISIS_SD_TRANSPORT);
    sd_write32(base + GENISIS_SPI_RX_BLOCK, GENISIS_SPI_RX_START | bytes);
    unsigned received = 0, budget = 200000;
    while (received < bytes && budget--)
    {
        status = sd_read32(base + GENISIS_SPI_STATUS);
        unsigned words = GENISIS_SPI_WORDS(status);
        if (words > (bytes - received + 3u) / 4u)
            return block_error(base, GENISIS_SD_TRANSPORT);
        if (!words)
        {
            if (status & GENISIS_SPI_DONE)
                return block_error(base, GENISIS_SD_TRANSPORT);
            continue;
        }
        while (words--)
        {
            uint32_t word = sd_read32(base + GENISIS_SPI_RX_POP);
            unsigned remaining = bytes - received;
            if (remaining >= 4u && !((uintptr_t)(data + received) & 3u))
            {
                *(sd_alias_word *)(void *)(data + received) = word;
                received += 4u;
            }
            else
            {
                unsigned take = remaining < 4u ? remaining : 4u;
                for (unsigned byte = 0; byte < take; ++byte)
                    data[received++] = (unsigned char)(word >> (byte * 8u));
            }
        }
    }
    if (received != bytes)
        return block_error(base, GENISIS_SD_TIMEOUT);
    budget = 200000;
    while (budget--)
    {
        status = sd_read32(base + GENISIS_SPI_STATUS);
        if (status & GENISIS_SPI_DONE)
        {
            if ((status & GENISIS_SPI_BUSY) || GENISIS_SPI_WORDS(status))
                return block_error(base, GENISIS_SD_TRANSPORT);
            /* A bad CRC is already idle and drained: preserve CS for CMD12. */
            return status & GENISIS_SPI_CRC_OK ? GENISIS_SD_READY : GENISIS_SD_CRC;
        }
    }
    return block_error(base, GENISIS_SD_TIMEOUT);
}

static int receive(uintptr_t base, unsigned char *data, unsigned bytes)
{
    unsigned budget = 10000;
    int byte;
    do
    {
        byte = transfer(base, 255);
        if (byte < 0)
            return GENISIS_SD_TRANSPORT;
    } while (byte == 255 && --budget);
    if (byte != 254)
        return budget ? GENISIS_SD_RESPONSE : GENISIS_SD_TIMEOUT;
    uint32_t status = sd_read32(base + GENISIS_SPI_STATUS);
    if ((status & GENISIS_SPI_CAP_RX_BLOCK) &&
        sd_read32(base + GENISIS_SPI_RX_BLOCK) == GENISIS_SPI_RX_MAGIC)
        return receive_block(base, data, bytes);
    uint16_t crc = 0;
    for (unsigned i = 0; i < bytes; ++i)
    {
        byte = transfer(base, 255);
        if (byte < 0)
            return GENISIS_SD_TRANSPORT;
        data[i] = (unsigned char)byte;
        crc = crc_byte(crc, data[i]);
    }
    int high = transfer(base, 255), low = transfer(base, 255);
    if (high < 0 || low < 0)
        return GENISIS_SD_TRANSPORT;
    return crc == (uint16_t)((unsigned)high * 256u + (unsigned)low) ? GENISIS_SD_READY
                                                                    : GENISIS_SD_CRC;
}

int genisis_sd_decode_csd(const unsigned char *csd, struct genisis_sd_card *card)
{
    unsigned version = csd[0] >> 6;
    uint32_t blocks;
    if (version == 1)
    {
        uint32_t size = ((uint32_t)(csd[7] & 63u) << 16) | ((uint32_t)csd[8] << 8) | csd[9];
        /* Exclude the 2 TiB endpoint that cannot be represented as block count
         * in this provisional 32-bit block API. Do not let it wrap to zero. */
        if (size == 0x3fffffu || !card->high_capacity)
            return 0;
        blocks = (size + 1u) << 10;
    }
    else if (version == 0)
    {
        unsigned read_length = csd[5] & 15u;
        unsigned mult = ((csd[9] & 3u) << 1) | (csd[10] >> 7);
        uint32_t size = ((uint32_t)(csd[6] & 3u) << 10) | ((uint32_t)csd[7] << 2) | (csd[8] >> 6);
        if (card->high_capacity || read_length < 9 || read_length > 11)
            return 0;
        blocks = (size + 1u) << (mult + 2u + read_length - 9u);
    }
    else
        return 0;
    if (!blocks)
        return 0;
    card->blocks = blocks;
    card->capacity_mib = blocks >> 11;
    return 1;
}

/* TRAN_SPEED multiplies a decimal unit (100 kHz, 1 MHz, 10 MHz, 100 MHz)
 * by a mantissa. Codes 1..15 encode 1.0, 1.2, 1.3, 1.5, 2.0, ..., 8.0.
 * At unit 1 MHz, code 11 is the first rate >=5 MHz. Reject reserved encodings
 * when selecting the faster SPI clock. */
static int supports_spi5(const unsigned char *csd)
{
    unsigned speed = csd[3], unit = speed & 7u, value = (speed >> 3) & 15u;
    return !(speed & 128u) && value && unit < 4u && (unit >= 2u || (unit == 1u && value >= 11u));
}

int genisis_sd_read(uintptr_t base, const struct genisis_sd_card *card, uint32_t block,
                    unsigned char *data)
{
    if (card->status != GENISIS_SD_READY || block >= card->blocks ||
        (!card->high_capacity && block > UINT32_MAX / 512u))
        return GENISIS_SD_RESPONSE;
    int status = GENISIS_SD_RESPONSE;
    if (command(base, 17, card->high_capacity ? block : block * 512u, 1) == 0)
        status = receive(base, data, 512);
    deselect(base);
    return status;
}

/* Keep CS asserted when CMD12 stops CMD18. Consume the mandatory stuff
 * byte before polling the R1 response and subsequent R1b busy interval. */
static int stop_read(uintptr_t base)
{
    if (sd_read32(base + GENISIS_SPI_STATUS) & GENISIS_SPI_BUSY)
        sd_write32(base + GENISIS_SPI_ABORT, 1u);
    /* Reselect before STOP because transport ABORT releases CS. */
    sd_write32(base + 4u, 0);
    if (transfer(base, 0x4cu) < 0)
        return GENISIS_SD_TRANSPORT;
    for (unsigned i = 0; i < 4; ++i)
        if (transfer(base, 0) < 0)
            return GENISIS_SD_TRANSPORT;
    if (transfer(base, 1) < 0 || transfer(base, 255) < 0)
        return GENISIS_SD_TRANSPORT;
    int response = 255;
    unsigned budget = 8;
    do
    {
        response = transfer(base, 255);
        if (response < 0)
            return GENISIS_SD_TRANSPORT;
        if (!(response & 128))
            break;
    } while (--budget);
    if (response != 0)
        return budget ? GENISIS_SD_RESPONSE : GENISIS_SD_TIMEOUT;
    budget = 100000;
    do
    {
        int byte = transfer(base, 255);
        if (byte < 0)
            return GENISIS_SD_TRANSPORT;
        if (byte == 255)
            return GENISIS_SD_READY;
    } while (--budget);
    return GENISIS_SD_TIMEOUT;
}

int genisis_sd_read_blocks(uintptr_t base, const struct genisis_sd_card *card, uint32_t block,
                           uint32_t count, unsigned char *data)
{
    if (card->status != GENISIS_SD_READY || block >= card->blocks || count > card->blocks - block ||
        count > UINT32_MAX / 512u ||
        (!card->high_capacity &&
         (block > UINT32_MAX / 512u || (count && count - 1u > UINT32_MAX / 512u - block))))
        return GENISIS_SD_RESPONSE;
    if (!count)
        return GENISIS_SD_READY;
    if (!data || (uintptr_t)data > UINT32_MAX - count * 512u)
        return GENISIS_SD_RESPONSE;
    if (count == 1)
        return genisis_sd_read(base, card, block, data);
    uint32_t capabilities = sd_read32(base + GENISIS_SPI_STATUS);
    if (!(capabilities & GENISIS_SPI_CAP_RX_BLOCK) ||
        sd_read32(base + GENISIS_SPI_RX_BLOCK) != GENISIS_SPI_RX_MAGIC)
    {
        /* The installed legacy controller keeps the qualified CMD17/table path.
         * Never access the new register window without STATUS capability. */
        for (uint32_t i = 0; i < count; ++i)
        {
            int status = genisis_sd_read(base, card, block + i, data + i * 512u);
            if (status != GENISIS_SD_READY)
                return status;
        }
        return GENISIS_SD_READY;
    }
    int response = command(base, 18, card->high_capacity ? block : block * 512u, 1);
    if (response != 0)
    {
        deselect(base);
        return GENISIS_SD_RESPONSE;
    }
    int status = GENISIS_SD_READY;
    for (uint32_t i = 0; i < count; ++i)
    {
        status = receive(base, data + i * 512u, 512);
        if (status != GENISIS_SD_READY)
            break;
    }
    /* Stop the stream after data/CRC errors and return the first error. */
    int stopped = stop_read(base);
    if (status == GENISIS_SD_READY)
        status = stopped;
    deselect(base);
    return status;
}

int genisis_sd_identify(uintptr_t base, struct genisis_sd_card *card)
{
    card->status = GENISIS_SD_ABSENT;
    card->blocks = card->capacity_mib = card->high_capacity = card->mbr_signature = 0;
    if (!(sd_read32(base + 12u) & 2u))
        return 0;
    card->status = GENISIS_SD_TRANSPORT;
    sd_write32(base, 125);
    sd_write32(base + 4u, 1);
    for (unsigned i = 0; i < 10; ++i)
        if (transfer(base, 255) < 0)
            goto done;
    card->status = GENISIS_SD_RESPONSE;
    if (command(base, 0, 0, 0x95) != 1)
        goto done;
    int reply = command(base, 8, 0x1aa, 0x87);
    unsigned v2 = reply == 1;
    if (v2)
    {
        unsigned char r7[4];
        for (unsigned i = 0; i < 4; ++i)
        {
            int byte = transfer(base, 255);
            if (byte < 0)
                goto done;
            r7[i] = (unsigned char)byte;
        }
        if (r7[0] || r7[1] || r7[2] != 1 || r7[3] != 0xaa)
            goto done;
    }
    else if (reply != 5)
        goto done; // CMD8 illegal on SD v1.
    card->status = GENISIS_SD_TIMEOUT;
    unsigned tries = 1000;
    do
    {
        reply = command(base, 55, 0, 1);
        if (reply != 0 && reply != 1)
            goto done;
        reply = command(base, 41, v2 ? 0x40000000u : 0, 1);
        if (reply == 0)
            break;
        if (reply != 1)
            goto done;
    } while (--tries);
    if (!tries)
        goto done;
    card->status = GENISIS_SD_RESPONSE;
    if (command(base, 58, 0, 1) != 0)
        goto done;
    unsigned char ocr[4];
    for (unsigned i = 0; i < 4; ++i)
    {
        int byte = transfer(base, 255);
        if (byte < 0)
            goto done;
        ocr[i] = (unsigned char)byte;
    }
    if (!(ocr[0] & 128u) || !(ocr[1] & 0x30u))
        goto done; // Card must accept the 3.3 V supply window.
    card->high_capacity = (unsigned)(v2 && (ocr[0] & 64u));
    if (!card->high_capacity && command(base, 16, 512, 1) != 0)
        goto done;
    unsigned char csd[16];
    if (command(base, 9, 0, 1) != 0)
        goto done;
    card->status = (uint32_t)receive(base, csd, 16);
    if (card->status != GENISIS_SD_READY)
        goto done;
    if (!genisis_sd_decode_csd(csd, card))
    {
        card->status = GENISIS_SD_CSD;
        goto done;
    }
    card->status = GENISIS_SD_READY;
    /* Initialize at 120 kHz. With a 30 MHz source, DIV5 selects 3 MHz.
     * Select DIV3 for 5 MHz when both the FIFO controller and CSD support it. */
    deselect(base);
    uint32_t capabilities = sd_read32(base + GENISIS_SPI_STATUS);
    unsigned fast = (capabilities & GENISIS_SPI_CAP_RX_BLOCK) &&
                    sd_read32(base + GENISIS_SPI_RX_BLOCK) == GENISIS_SPI_RX_MAGIC &&
                    supports_spi5(csd);
    sd_write32(base, fast ? 3u : 5u);
    unsigned char sector[512];
    card->status = (uint32_t)genisis_sd_read(base, card, 0, sector);
    if (card->status == GENISIS_SD_READY)
        card->mbr_signature = sector[510] == 0x55 && sector[511] == 0xaa;
done:
    deselect(base);
    return card->status == GENISIS_SD_READY;
}
