/* Detect the BRAM text-console controller independently of monitor presence. */
#ifndef GENISIS_VIDEO_H
#define GENISIS_VIDEO_H
#include <stdint.h>
int genisis_video_start(uintptr_t base);
void genisis_video_clear(void);
void genisis_video_putc(unsigned char byte);
/* Write cells directly in the 100x37, 16-colour text window.
 * These writes leave UART output unchanged. */
void genisis_video_fill(unsigned x, unsigned y, unsigned width, unsigned height,
                        unsigned char glyph, unsigned char attr);
void genisis_video_text(unsigned x, unsigned y, const char *text, unsigned char attr);
void genisis_video_console(unsigned x, unsigned y, unsigned width, unsigned height,
                           unsigned char attr);
void genisis_video_mirror(int enabled);
#endif
