/* HID usages and terminal escape sequences share UI actions, not a byte FIFO.
 * A bounded incomplete-escape timeout lets a standalone UART Escape work. */
#include "input.h"
#include "genisis.h"
static unsigned sequence, number, budget;

static int terminal(int c)
{
    if (!sequence)
    {
        if (c == 27)
        {
            sequence = 1;
            number = 0;
            budget = 2000;
            return -1;
        }
        return c;
    }
    if (sequence == 1)
    {
        if (c == '[' || c == 'O')
        {
            sequence = 2;
            budget = 2000;
            return -1;
        }
        sequence = 0;
        return c;
    }
    if (c >= '0' && c <= '9')
    {
        number = number < 100 ? number * 10 + (unsigned)(c - '0') : 100;
        return -1;
    }
    sequence = 0;
    if (c == 'A')
        return GENISIS_KEY_UP;
    if (c == 'B')
        return GENISIS_KEY_DOWN;
    if (c == 'C')
        return GENISIS_KEY_RIGHT;
    if (c == 'D')
        return GENISIS_KEY_LEFT;
    if (c == 'P' && !number)
        return GENISIS_KEY_F1;
    if (c == '~')
    {
        if (number == 11)
            return GENISIS_KEY_F1;
        if (number == 15)
            return GENISIS_KEY_F5;
        if (number == 21)
            return GENISIS_KEY_F10;
        if (number == 3)
            return 127;
    }
    return -1;
}

int genisis_input_poll(const struct genisis_platform *p)
{
    if (genisis_hal_read32(GENISIS_UART_BASE + 4u) & 2u)
        return terminal(genisis_hal_get_byte(0));
    if (sequence && budget && !--budget)
    {
        int k = sequence == 1 ? 27 : -1;
        sequence = 0;
        return k;
    }
    if (!p || !(p->integrated & GENISIS_KEYBOARD) ||
        !(genisis_hal_read32(p->keyboard_base + 4u) & 4u))
        return -1;
    unsigned u = genisis_hal_read32(p->keyboard_base + 8u) & 255u;
    if (u >= 0x1eu && u <= 0x26u)
        return '1' + (int)(u - 0x1eu);
    if (u == 0x27u || u == 0x62u)
        return '0';
    if (u >= 0x59u && u <= 0x61u)
        return '1' + (int)(u - 0x59u);
    if (u == 0x28u || u == 0x58u)
        return '\r';
    if (u == 0x29u)
        return 27;
    if (u == 0x2au)
        return 8;
    if (u == 0x4cu)
        return 127;
    if (u == 0x52u)
        return GENISIS_KEY_UP;
    if (u == 0x51u)
        return GENISIS_KEY_DOWN;
    if (u == 0x50u)
        return GENISIS_KEY_LEFT;
    if (u == 0x4fu)
        return GENISIS_KEY_RIGHT;
    if (u == 0x3au)
        return GENISIS_KEY_F1;
    if (u == 0x3eu)
        return GENISIS_KEY_F5;
    if (u == 0x43u)
        return GENISIS_KEY_F10;
    if (u == 0x0cu)
        return 'I';
    if (u == 0x15u)
        return 'R';
    if (u == 0x19u)
        return 'V';
    if (u == 0x11u)
        return 'N';
    return -1;
}

int genisis_input_wait(const struct genisis_platform *p)
{
    int k;
    do
    {
        k = genisis_input_poll(p);
    } while (k < 0);
    return k;
}
