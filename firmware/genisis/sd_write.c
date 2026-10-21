/* SD block writes use the same bounded SPI and CRC primitives as reads.
 * Only initialized cards and LBAs below 262144 are accepted.
 */
#include "sd.c"

int r32_sd_write(uintptr_t base, const struct genisis_sd_card *card, unsigned lba,
                 const unsigned char *data)
{
    if (card->status != GENISIS_SD_READY || lba >= card->blocks || lba >= 262144u ||
        (!card->high_capacity && lba > UINT32_MAX / 512u))
        return GENISIS_SD_RESPONSE;
    int result = GENISIS_SD_RESPONSE;
    if (command(base, 24, card->high_capacity ? lba : lba * 512u, 1) != 0)
        goto done;
    if (transfer(base, 255) < 0 || transfer(base, 254) < 0)
    {
        result = GENISIS_SD_TRANSPORT;
        goto done;
    }
    uint16_t crc = 0;
    for (unsigned i = 0; i < 512; i++)
    {
        crc = crc_byte(crc, data[i]);
        if (transfer(base, data[i]) < 0)
        {
            result = GENISIS_SD_TRANSPORT;
            goto done;
        }
    }
    if (transfer(base, crc >> 8) < 0 || transfer(base, crc & 255) < 0)
    {
        result = GENISIS_SD_TRANSPORT;
        goto done;
    }
    int token = transfer(base, 255);
    if (token < 0)
    {
        result = GENISIS_SD_TRANSPORT;
        goto done;
    }
    if ((token & 31) != 5)
        goto done;
    result = GENISIS_SD_TIMEOUT;
    for (unsigned budget = 100000; budget; --budget)
    {
        int v = transfer(base, 255);
        if (v < 0)
        {
            result = GENISIS_SD_TRANSPORT;
            break;
        }
        if (v == 255)
        {
            result = GENISIS_SD_READY;
            break;
        }
    }
done:
    deselect(base);
    return result;
}
