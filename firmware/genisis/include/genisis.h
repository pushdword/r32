/* Formato Genisis v1 partilhado pelo firmware e pelo kernel.
 * Todos os campos são uint32_t little-endian. */
#ifndef GENISIS_H
#define GENISIS_H
#include <stdint.h>
#define GENISIS_MAGIC 0x4b323352u      /* Bytes "R32K". */
#define GENISIS_INFO_MAGIC 0x524e4547u /* Bytes "GENR". */
#define GENISIS_VERSION 1u
#define GENISIS_SDRAM_BASE 0x10000000u
#define GENISIS_LOAD_MIN 0x10010000u /* Primeiros 64 KiB reservados ao arranque. */
#define GENISIS_LOAD_END 0x13e00000u /* Últimos 2 MiB reservados a pilhas de arranque. */
#define GENISIS_UART_BASE 0xf0000000u
#define GENISIS_UART_DATA (*(volatile uint8_t *)(uintptr_t)GENISIS_UART_BASE)
#define GENISIS_UART_STATUS (*(volatile uint32_t *)(uintptr_t)(GENISIS_UART_BASE + 4u))

/* Header de 32 bytes seguido de file_bytes. memory_bytes inclui BSS.
 * CRC32/ISO-HDLC cobre o payload. flags=0 exige o perfil sem cache. */
struct genisis_image
{
    uint32_t magic, version, load, file_bytes, memory_bytes, entry, crc32, flags;
};

/* Estrutura de handoff passada em a0 na entrada do kernel. */
struct genisis_boot_info
{
    uint32_t magic, version, size, stage, error, memory_base, memory_bytes;
    uint32_t uart_base, uart_baud, source, image_start, image_end, entry, flags;
};

/* Rotinas pequenas de debug disponíveis em BRAM e num kernel sem libc.
 * O mesmo MMIO alimenta o UART simulado e a ponte USB/UART física do Dock. */
static inline void genisis_putc(unsigned char byte)
{
    while (!(GENISIS_UART_STATUS & 1u))
    {
    }
    GENISIS_UART_DATA = byte;
}

static inline void genisis_puts(const char *text)
{
    while (*text)
        genisis_putc((unsigned char)*text++);
}

static inline void genisis_flush(void)
{
    while (!(GENISIS_UART_STATUS & 1u))
    {
    }
}
#endif
