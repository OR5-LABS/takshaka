/*
 * dhry.h — Dhrystone 2.1 type and macro definitions
 * Adapted for bare-metal RISC-V (Takshaka SoC).
 * Dhrystone was written by R. P. Weicker.
 */
#ifndef DHRY_H
#define DHRY_H

#include <stdint.h>

/* --- Dhrystone types ------------------------------------------------------- */
typedef int            One_Thirty;
typedef int            One_Fifty;
typedef char           Capital_Letter;
typedef int            Boolean;
typedef char          *Str_30;
typedef int            Arr_1_Dim[50];
typedef int            Arr_2_Dim[50][50];

typedef enum {
    Ident_1, Ident_2, Ident_3, Ident_4, Ident_5
} Enumeration;

typedef struct Record *Rec_Pointer;
typedef struct Record {
    Rec_Pointer     Ptr_Comp;
    Enumeration     Discr;
    union {
        struct {
            Enumeration Enum_Comp;
            int         Int_Comp;
            char        Str_Comp[31];
        } var_1;
        struct {
            Enumeration E_Comp_2;
            char        Str_2_Comp[31];
        } var_2;
        struct {
            char Ch_1_Comp;
            char Ch_2_Comp;
        } var_3;
    } variant;
} Rec_Type;

/* --- Constants ------------------------------------------------------------- */
#define TRUE    1
#define FALSE   0

/* --- UART output ----------------------------------------------------------- */
void uart_putc(char c);
int  dhr_printf(const char *fmt, ...);

/* --- Timer ----------------------------------------------------------------- */
uint32_t read_mtime(void);

/* --- Number of runs (compile-time, overridable via -DNUMBER_OF_RUNS=xxx) --- */
#ifndef NUMBER_OF_RUNS
#define NUMBER_OF_RUNS 500000
#endif

/* --- Clock frequency (100 MHz for Takshaka FPGA / 50 MHz sim mtime) --------- */
#ifndef CLK_FREQ_HZ
#define CLK_FREQ_HZ 100000000
#endif

#endif /* DHRY_H */
