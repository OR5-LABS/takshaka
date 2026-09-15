/* core_portme.h — Takshaka bare-metal CoreMark port */
#ifndef CORE_PORTME_H
#define CORE_PORTME_H

#include <stdint.h>
#include <stddef.h>

/* ---- CoreMark required data types ---------------------------------------- */
typedef int16_t    ee_s16;
typedef uint16_t   ee_u16;
typedef int32_t    ee_s32;
typedef uint32_t   ee_u32;
typedef int8_t     ee_s8;
typedef uint8_t    ee_u8;
typedef size_t     ee_size_t;
typedef uintptr_t  ee_ptr_int;   /* integer wide enough to hold a pointer */
typedef uint32_t   CORE_TICKS;

typedef struct { ee_u8 portable_id; } core_portable;

/* ---- Build-time configuration -------------------------------------------- */
#define COMPILER_VERSION  "GCC " __VERSION__
#define COMPILER_FLAGS    "-O2 -march=rv32im -mabi=ilp32"
#define MEM_LOCATION      "STATIC"
#define MEM_METHOD        MEM_STATIC
#define MULTITHREAD       1
#define USE_PTHREAD       0
#define USE_FORK          0
#define MAIN_HAS_NOARGC   1
#define MAIN_HAS_NORETURN 0
#define SEED_METHOD       SEED_VOLATILE
#define HAS_FLOAT         0
#define HAS_TIME_H        0
#define USE_CLOCK         0
#define HAS_STDIO         0
#define HAS_PRINTF        0   /* 0 = use our ee_printf, not stdlib printf */
#define TIMER_RES_DIVIDER 1
#define ITERATIONS_SCALE  1

/* Number of parallel contexts (1 = single-threaded) */
extern ee_u32 default_num_contexts;

/* ---- Timing (mtime = cycle counter) -------------------------------------- */
extern uint32_t baremetal_start_time(void);
extern uint32_t baremetal_stop_time(void);

#define START_TIMER()        baremetal_start_time()
#define STOP_TIMER()         baremetal_stop_time()
#define MYTIMEDIFF(f,s)      ((s) - (f))
#ifndef EE_TICKS_PER_SEC
#define EE_TICKS_PER_SEC     (100000000UL)  /* 100 MHz nominal */
#endif

/* ---- UART printf (no stdlib) --------------------------------------------- */
int ee_printf(const char *fmt, ...);

/* ---- Function prototypes expected by CoreMark ---------------------------- */
void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);
void *align_mem(void *ptr);

#endif /* CORE_PORTME_H */
