/* BIOS panels and menus rendered through the text-cell interface. */
#ifndef GENISIS_UI_H
#define GENISIS_UI_H
#include "hal.h"
#include "sd.h"
#include "rtc.h"
#include "w5500.h"
#include "post.h"
/* TF image path shared by the loader and boot display. */
#ifndef GENISIS_TF_BOOT_PATH
#define GENISIS_TF_BOOT_PATH "/boot/uboot.r32"
#endif
enum
{
    GENISIS_BOOT_OPEN,
    GENISIS_BOOT_HEADER,
    GENISIS_BOOT_READ,
    GENISIS_BOOT_VERIFY,
    GENISIS_BOOT_CLEAR,
    GENISIS_BOOT_READY,
    GENISIS_BOOT_ERROR
};

const char *genisis_ui_boot_phase(unsigned phase);
void genisis_ui_boot_progress(unsigned phase, uint32_t done, uint32_t total, unsigned percent);

struct genisis_ui_state
{
    const struct genisis_platform *platform;
    const struct genisis_sd_card *card;
    const struct genisis_rtc *rtc;
    const struct genisis_w5500 *nic;
    const struct genisis_post_result *post;
};

enum
{
    GENISIS_UI_MAIN,
    GENISIS_UI_CPU,
    GENISIS_UI_DEVICES,
    GENISIS_UI_TESTS,
    GENISIS_UI_BOOT,
    GENISIS_UI_EXIT,
    GENISIS_UI_PAGES
};

void genisis_ui_post(const struct genisis_ui_state *state, int complete);
void genisis_ui_progress(unsigned phase, uint32_t done, uint32_t total);
unsigned genisis_ui_items(unsigned page);
unsigned genisis_ui_action(unsigned page, unsigned item);
void genisis_ui_menu(const struct genisis_ui_state *state, unsigned page, unsigned item);
void genisis_ui_dialog(unsigned page, const char *title, const char *help);
void genisis_ui_help(void);
#endif
