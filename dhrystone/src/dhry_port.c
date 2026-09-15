/*
 * dhry_port.c — Bare-metal RISC-V port for the Takshaka SoC.
 *
 * Provides:
 *   uart_putc()   — write one byte to the UART TX register
 *   dhr_printf()  — minimal printf (int, char, string via uart_putc)
 *   read_mtime()  — return mtime[31:0] from CLINT
 */
#include "dhry.h"
#include <stdarg.h>
#include <stdint.h>

/* ---- UART ----------------------------------------------------------------- */
#define UART_BASE 0x10000000U

void uart_putc(char c)
{
    volatile uint32_t *uart = (volatile uint32_t *)UART_BASE;
    /* bit 0 of status = tx_busy; wait until free */
    while ((*uart) & 1u)
        ;
    *uart = (uint32_t)(unsigned char)c;
}

static void uart_puts(const char *s)
{
    while (*s) uart_putc(*s++);
}

/* ---- Minimal printf ------------------------------------------------------- */
static void print_uint(uint32_t v, int base)
{
    char buf[12];
    int  n = 0;
    if (v == 0) { uart_putc('0'); return; }
    while (v) {
        buf[n++] = "0123456789abcdef"[v % base];
        v /= base;
    }
    while (n--) uart_putc(buf[n + 1]);   /* +1 because n was post-decremented */
}

static void print_uint_rev(uint32_t v, int base)
{
    char buf[12];
    int  n = 0;
    if (v == 0) { uart_putc('0'); return; }
    while (v) {
        buf[n++] = "0123456789abcdef"[v % base];
        v /= base;
    }
    for (int i = n - 1; i >= 0; i--) uart_putc(buf[i]);
}

int dhr_printf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int count = 0;
    while (*fmt) {
        if (*fmt != '%') {
            uart_putc(*fmt++);
            count++;
            continue;
        }
        fmt++;  /* skip '%' */

        /* Optional zero-pad and width */
        char pad = ' ';
        if (*fmt == '0') { pad = '0'; fmt++; }
        int width = 0;
        while (*fmt >= '0' && *fmt <= '9')
            width = width * 10 + (*fmt++ - '0');

        switch (*fmt) {
            case 'd': {
                int v = va_arg(ap, int);
                char tmp[12]; int n = 0;
                if (v < 0) { uart_putc('-'); v = -v; count++; }
                unsigned uv = (unsigned)v;
                if (uv == 0) tmp[n++] = '0';
                while (uv) { tmp[n++] = '0' + uv % 10; uv /= 10; }
                /* pad to width */
                for (int p = n; p < width; p++) { uart_putc(pad); count++; }
                for (int i = n - 1; i >= 0; i--) { uart_putc(tmp[i]); count++; }
                break;
            }
            case 'u': {
                uint32_t v = va_arg(ap, uint32_t);
                char tmp[12]; int n = 0;
                if (v == 0) tmp[n++] = '0';
                while (v) { tmp[n++] = '0' + v % 10; v /= 10; }
                for (int p = n; p < width; p++) { uart_putc(pad); count++; }
                for (int i = n - 1; i >= 0; i--) { uart_putc(tmp[i]); count++; }
                break;
            }
            case 'x': {
                uint32_t v = va_arg(ap, uint32_t);
                char tmp[9]; int n = 0;
                if (v == 0) tmp[n++] = '0';
                while (v) { tmp[n++] = "0123456789abcdef"[v % 16]; v /= 16; }
                for (int p = n; p < width; p++) { uart_putc(pad); count++; }
                for (int i = n - 1; i >= 0; i--) { uart_putc(tmp[i]); count++; }
                break;
            }
            case 'c':
                uart_putc((char)va_arg(ap, int)); count++;
                break;
            case 's': {
                const char *s = va_arg(ap, const char *);
                while (*s) { uart_putc(*s++); count++; }
                break;
            }
            case '%':
                uart_putc('%'); count++;
                break;
            default:
                uart_putc('%'); uart_putc(*fmt); count += 2;
                break;
        }
        fmt++;
    }
    va_end(ap);
    return count;
}

/* ---- Timer ---------------------------------------------------------------- */
#define MTIME_LO 0x0200BFF8U

uint32_t read_mtime(void)
{
    return *(volatile uint32_t *)MTIME_LO;
}
