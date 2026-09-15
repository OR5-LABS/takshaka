/* core_portme.c — Takshaka bare-metal CoreMark port */
/* Include coremark.h (which includes core_portme.h) so secs_ret is available */
#include "coremark.h"
#include <stdarg.h>
#include <stdint.h>

/* ---- CoreMark required volatile seeds ------------------------------------ */
#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PROFILE_RUN
volatile ee_s32 seed1_volatile = 0x8;
volatile ee_s32 seed2_volatile = 0x8;
volatile ee_s32 seed3_volatile = 0x8;
#endif
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

/* ---- Number of parallel contexts (single-threaded = 1) ------------------- */
ee_u32 default_num_contexts = MULTITHREAD;

/* ---- SoC MMIO ------------------------------------------------------------ */
#define MTIME_LO  (*(volatile uint32_t *)0x0200BFF8U)
#define UART_TX   (*(volatile uint32_t *)0x10000000U)

/* ---- Timing (mtime = simulated cycle counter, 1 tick = 1 clock cycle) --- */
static CORE_TICKS _start_tick, _stop_tick;

void start_time(void) { _start_tick = MTIME_LO; }
void stop_time(void)  { _stop_tick  = MTIME_LO; }

CORE_TICKS get_time(void) {
    return (CORE_TICKS)(_stop_tick - _start_tick);
}

/* time_in_secs: convert cycle-count ticks to seconds. */
secs_ret time_in_secs(CORE_TICKS ticks) {
    return (secs_ret)ticks / (secs_ret)EE_TICKS_PER_SEC;
}

uint32_t baremetal_start_time(void) { return MTIME_LO; }
uint32_t baremetal_stop_time(void)  { return MTIME_LO; }

/* ---- align_mem ----------------------------------------------------------- */
void *align_mem(void *ptr) {
    uintptr_t p = (uintptr_t)ptr;
    return (void *)((p + 3) & ~(uintptr_t)3);
}

/* ---- Minimal libc stubs (memset / memcpy) -------------------------------- */
void *memset(void *dst, int c, size_t n) {
    unsigned char *d = (unsigned char *)dst;
    while (n--) *d++ = (unsigned char)c;
    return dst;
}
void *memcpy(void *dst, const void *src, size_t n) {
    unsigned char *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;
    while (n--) *d++ = *s++;
    return dst;
}

/* ---- UART output --------------------------------------------------------- */
static void _putc(char c) {
    if (c == '\n') _putc('\r');
    volatile uint32_t *uart = (volatile uint32_t *)0x10000000U;
    while ((*uart) & 1u)
        ;
    *uart = (uint32_t)(unsigned char)c;
}
static void _puts(const char *s) { while (*s) _putc(*s++); }

static void _print_uint(unsigned long v) {
    char b[20]; int i = 0;
    if (v == 0) { _putc('0'); return; }
    while (v) { b[i++] = '0' + (int)(v % 10); v /= 10; }
    for (int j = i-1; j >= 0; j--) _putc(b[j]);
}
static void _print_int(long v) {
    if (v < 0) { _putc('-'); _print_uint((unsigned long)-v); }
    else _print_uint((unsigned long)v);
}
static void _print_hex(unsigned long v, int width) {
    const char *h = "0123456789abcdef";
    char b[16]; int i = 0;
    do { b[i++] = h[v & 0xF]; v >>= 4; } while (v);
    while (i < width) b[i++] = '0';
    for (int j = i-1; j >= 0; j--) _putc(b[j]);
}

/* ee_printf: covers all format specifiers used by CoreMark */
int ee_printf(const char *fmt, ...) {
    va_list ap; va_start(ap, fmt); int n = 0;
    for (; *fmt; fmt++) {
        if (*fmt != '%') { _putc(*fmt); n++; continue; }
        fmt++;
        int width = 0;
        while (*fmt >= '0' && *fmt <= '9') { width = width*10 + (*fmt-'0'); fmt++; }
        int lng = 0;
        if (*fmt == 'l') { lng = 1; fmt++; }
        switch (*fmt) {
          case '%': _putc('%'); break;
          case 'c': _putc((char)va_arg(ap, int)); break;
          case 's': _puts(va_arg(ap, const char *)); break;
          case 'd': case 'i':
            _print_int(lng ? va_arg(ap,long) : (long)va_arg(ap,int)); break;
          case 'u':
            _print_uint(lng ? va_arg(ap,unsigned long) : (unsigned long)va_arg(ap,unsigned)); break;
          case 'x': case 'X':
            _print_hex(lng ? va_arg(ap,unsigned long) : (unsigned long)va_arg(ap,unsigned), width); break;
          default: _putc('%'); if (lng) _putc('l'); _putc(*fmt); break;
        }
        n++;
    }
    va_end(ap); return n;
}

/* ---- Port init/fini ------------------------------------------------------ */
void portable_init(core_portable *p, int *argc, char *argv[]) {
    (void)argc; (void)argv;
    if (sizeof(ee_ptr_int) != sizeof(ee_u8 *))
        ee_printf("ERROR: ee_ptr_int size mismatch!\n");
    if (sizeof(ee_u32) != 4)
        ee_printf("ERROR: ee_u32 is not 32-bit!\n");
    p->portable_id = 1;
}
void portable_fini(core_portable *p) { p->portable_id = 0; }
