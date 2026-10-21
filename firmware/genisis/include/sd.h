/* SD SPI identification and reads over the HAL byte transport. */
#ifndef GENISIS_SD_H
#define GENISIS_SD_H
#include <stdint.h>
/* Discover RX-block support through STATUS and the SBF1 signature.
 * RX_BLOCK bit31 starts a 1..512-byte read. RX_POP returns LE32 payload words.
 * FIFO counts include padded final words and exclude CRC bytes.
 * DONE/CRC_OK remain set until a valid START, ABORT or reset. */
#define GENISIS_SPI_STATUS 12u
#define GENISIS_SPI_ABORT 20u
#define GENISIS_SPI_RX_BLOCK 24u
#define GENISIS_SPI_RX_POP 28u
#define GENISIS_SPI_CAP_RX_BLOCK 0x80000000u
#define GENISIS_SPI_RX_START 0x80000000u
#define GENISIS_SPI_RX_MAGIC 0x31464253u
#define GENISIS_SPI_BUSY 1u
#define GENISIS_SPI_DONE 8u
#define GENISIS_SPI_CRC_OK 16u
#define GENISIS_SPI_WORDS(status) (((status) >> 8) & 255u)

enum genisis_sd_status
{
    GENISIS_SD_ABSENT = 0,
    GENISIS_SD_READY = 1,
    GENISIS_SD_TRANSPORT = 2,
    GENISIS_SD_RESPONSE = 3,
    GENISIS_SD_TIMEOUT = 4,
    GENISIS_SD_CSD = 5,
    GENISIS_SD_CRC = 6
};

struct genisis_sd_card
{
    uint32_t status, blocks, capacity_mib, high_capacity, mbr_signature;
};

int genisis_sd_identify(uintptr_t base, struct genisis_sd_card *card);
int genisis_sd_read(uintptr_t base, const struct genisis_sd_card *card, uint32_t block,
                    unsigned char *data);
/* Read contiguous blocks with CMD18/CMD12 on block-capable controllers.
 * Single-block reads and older controllers use CMD17. Return an error if
 * any block fails. */
int genisis_sd_read_blocks(uintptr_t base, const struct genisis_sd_card *card, uint32_t block,
                           uint32_t count, unsigned char *data);
int genisis_sd_decode_csd(const unsigned char *csd, struct genisis_sd_card *card);
#endif
