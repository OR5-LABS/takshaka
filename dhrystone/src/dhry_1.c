/*
 * dhry_1.c — Dhrystone 2.1 main benchmark loop.
 * Reference: R. P. Weicker, "Dhrystone: A Synthetic Systems Programming
 *            Benchmark", CACM Vol. 27(10), October 1984.
 * Adapted for bare-metal RISC-V Takshaka SoC.
 */
#include "dhry.h"
#include <string.h>

/* Record storage — kept in BSS so the linker puts them in DRAM on FPGA. */
Rec_Type Rec_glob_1;
Rec_Type Rec_glob_2;

Rec_Pointer Ptr_glob_next;
Rec_Pointer Ptr_glob;
Boolean     Bool_glob;
char        Ch_1_glob;
char        Ch_2_glob;
int         Int_glob;
Arr_1_Dim   Arr_1_glob;
Arr_2_Dim   Arr_2_glob;

/* Forward declarations for dhry_2.c */
extern Enumeration Func_1(Capital_Letter Ch_1_Par_Val, Capital_Letter Ch_2_Par_Val);
extern Boolean     Func_2(Str_30 Str_1_Par_Ref, Str_30 Str_2_Par_Ref);
extern Boolean     Func_3(Enumeration Enum_Par_Val);
extern void        Proc_6(Enumeration Enum_Val_Par, Enumeration *Enum_Ref_Par);
extern void        Proc_7(One_Fifty Int_1_Par_Val, One_Fifty Int_2_Par_Val, One_Fifty *Int_Par_Ref);
extern void        Proc_8(Arr_1_Dim Arr_1_Par_Ref, Arr_2_Dim Arr_2_Par_Ref,
                          int Int_1_Par_Val, int Int_2_Par_Val);

static void Proc_1(Rec_Pointer Ptr_Val_Par);
static void Proc_2(One_Fifty *Int_Par_Ref);
static void Proc_3(Rec_Pointer *Ptr_Ref_Par);
static void Proc_4(void);
static void Proc_5(void);

int main(void)
{
    Rec_Pointer Next_Ptr_Glob;
    int         Int_1_Loc, Int_2_Loc, Int_3_Loc;
    char        Ch_Index;
    Enumeration Enum_Loc;
    char        Str_1_Loc[31], Str_2_Loc[31];  /* local string storage */
    int         Run_Index;
    int         Number_Of_Runs = NUMBER_OF_RUNS;
    uint32_t    Begin_Time, End_Time, Elapsed;

    /* Initialise global records */
    Next_Ptr_Glob = &Rec_glob_2;
    Ptr_glob      = &Rec_glob_1;

    Ptr_glob->Ptr_Comp               = Next_Ptr_Glob;
    Ptr_glob->Discr                  = Ident_1;
    Ptr_glob->variant.var_1.Enum_Comp = Ident_3;
    Ptr_glob->variant.var_1.Int_Comp  = 40;
    strcpy(Ptr_glob->variant.var_1.Str_Comp, "DHRYSTONE PROGRAM, SOME STRING");

    strcpy(Str_1_Loc, "DHRYSTONE PROGRAM, 1'ST STRING");
    Arr_2_glob[8][7] = 10;   /* used in one branch of Proc_8 */

    /* ------------------------------------------------------------------ */
    dhr_printf("Dhrystone Benchmark, Version 2.1 (Language: C)\n");
    dhr_printf("Program compiled without 'register' attribute\n");
    dhr_printf("Execution starts, %d runs through Dhrystone\n", Number_Of_Runs);

    Begin_Time = read_mtime();

    for (Run_Index = 1; Run_Index <= Number_Of_Runs; ++Run_Index) {
        Proc_5();
        Proc_4();
        Int_1_Loc  = 2;
        Int_2_Loc  = 3;
        strcpy(Str_2_Loc, "DHRYSTONE PROGRAM, 2'ND STRING");
        Enum_Loc   = Ident_2;
        Bool_glob  = !Func_2(Str_1_Loc, Str_2_Loc);
        while (Int_1_Loc < Int_2_Loc) {
            Int_3_Loc = 5 * Int_1_Loc - Int_2_Loc;
            Proc_7(Int_1_Loc, Int_2_Loc, &Int_3_Loc);
            Int_1_Loc += 1;
        }
        Proc_8(Arr_1_glob, Arr_2_glob, Int_1_Loc, Int_3_Loc);
        Proc_1(Ptr_glob);
        for (Ch_Index = 'A'; Ch_Index <= Ch_2_glob; ++Ch_Index) {
            if (Enum_Loc == Func_1(Ch_Index, 'C')) {
                Proc_6(Ident_1, &Enum_Loc);
            }
        }
        Int_3_Loc  = Int_2_Loc * Int_1_Loc;
        Int_2_Loc  = Int_3_Loc / Int_1_Loc;
        Int_2_Loc  = 7 * (Int_3_Loc - Int_2_Loc) - Int_1_Loc;
        Proc_2(&Int_1_Loc);
    }

    End_Time = read_mtime();
    Elapsed  = End_Time - Begin_Time;   /* mtime ticks (1 tick/cycle) */

    dhr_printf("Execution ends\n\n");
    dhr_printf("Final values of the variables used in the benchmark:\n\n");
    dhr_printf("Int_Glob:            %d\n",  Int_glob);
    dhr_printf("Bool_Glob:           %d\n",  Bool_glob);
    dhr_printf("Ch_1_Glob:           %c\n",  Ch_1_glob);
    dhr_printf("Ch_2_Glob:           %c\n",  Ch_2_glob);
    dhr_printf("Arr_1_Glob[8]:       %d\n",  Arr_1_glob[8]);
    dhr_printf("Arr_2_Glob[8][7]:    %d\n",  Arr_2_glob[8][7]);
    dhr_printf("Ptr_Glob->Discr:     %d\n",  Ptr_glob->Discr);
    dhr_printf("        ->Int_Comp:  %d\n",  Ptr_glob->variant.var_1.Int_Comp);
    dhr_printf("Next_Ptr_Glob->Discr: %d\n", Next_Ptr_Glob->Discr);
    dhr_printf("        ->Int_Comp:  %d\n",  Next_Ptr_Glob->variant.var_1.Int_Comp);
    dhr_printf("Int_1_Loc:           %d\n",  Int_1_Loc);
    dhr_printf("Int_2_Loc:           %d\n",  Int_2_Loc);
    dhr_printf("Int_3_Loc:           %d\n",  Int_3_Loc);
    dhr_printf("Enum_Loc:            %d\n",  Enum_Loc);
    dhr_printf("Str_1_Loc:           %s\n",  Str_1_Loc);
    dhr_printf("Str_2_Loc:           %s\n",  Str_2_Loc);

    /* Score */
    uint32_t dhrystones_per_sec = 0;
    if (Elapsed > 0)
        dhrystones_per_sec = (uint32_t)(((uint64_t)Number_Of_Runs * CLK_FREQ_HZ) / Elapsed);

    uint32_t us_per_run = (Elapsed > 0)
        ? (uint32_t)(((uint64_t)Elapsed * 1000000ULL) /
                     ((uint64_t)Number_Of_Runs * CLK_FREQ_HZ))
        : 0;
    uint32_t mhz            = CLK_FREQ_HZ / 1000000;
    uint32_t dmips          = dhrystones_per_sec / 1757;
    uint32_t dmips_frac     = (dhrystones_per_sec % 1757) * 1000 / 1757;
    uint32_t dps_per_mhz    = (mhz > 0) ? dhrystones_per_sec / mhz : 0;
    uint32_t dmips_mhz      = dps_per_mhz / 1757;
    uint32_t dmips_mhz_frac = (dps_per_mhz % 1757) * 1000 / 1757;

    uint32_t cycles_per_iter = (Elapsed > 0) ? (Elapsed / Number_Of_Runs) : 0;

    dhr_printf("\n");
    dhr_printf("Cycles/Iteration:                            %d\n", cycles_per_iter);
    dhr_printf("Microseconds for one run through Dhrystone:  %d\n", us_per_run);
    dhr_printf("Dhrystones per Second:                       %d\n", dhrystones_per_sec);
    dhr_printf("DMIPS:                                       %d.%03d\n", dmips, dmips_frac);
    dhr_printf("DMIPS/MHz:                                   %d.%03d\n", dmips_mhz, dmips_mhz_frac);
    
#ifdef COMPILER_VERSION
    dhr_printf("Compiler Version:                            %s\n", COMPILER_VERSION);
#endif
#ifdef COMPILER_FLAGS
    dhr_printf("Compiler Flags:                              %s\n", COMPILER_FLAGS);
#endif
    dhr_printf("\n");

    /* Signal simulation end via tohost */
    volatile uint32_t *tohost = (volatile uint32_t *)0x20000000;
    *tohost = 1;

    while (1) ; /* halt */
    return 0;
}

/* ---- Procedures ----------------------------------------------------------- */

static void Proc_1(Rec_Pointer Ptr_Val_Par)
{
    Rec_Pointer Next = Ptr_Val_Par->Ptr_Comp;
    *Ptr_Val_Par->Ptr_Comp = *Ptr_glob;
    Ptr_Val_Par->variant.var_1.Int_Comp = 5;
    Next->variant.var_1.Int_Comp = Ptr_Val_Par->variant.var_1.Int_Comp;
    Next->Ptr_Comp = Ptr_Val_Par->Ptr_Comp;
    Proc_3(&Next->Ptr_Comp);
    if (Next->Discr == Ident_1) {
        Next->variant.var_1.Int_Comp = 6;
        Proc_6(Ptr_Val_Par->variant.var_1.Enum_Comp,
               &Next->variant.var_1.Enum_Comp);
        Next->Ptr_Comp = Ptr_glob->Ptr_Comp;
        Proc_7(Next->variant.var_1.Int_Comp, 10,
               &Next->variant.var_1.Int_Comp);
    } else {
        *Ptr_Val_Par = *Ptr_Val_Par->Ptr_Comp;
    }
}

static void Proc_2(One_Fifty *Int_Par_Ref)
{
    One_Fifty  Int_Loc;
    Enumeration Enum_Loc;
    Int_Loc = *Int_Par_Ref + 10;
    for (;;) {
        if (Ch_1_glob == 'A') {
            Int_Loc -= 1;
            *Int_Par_Ref = Int_Loc - Int_glob;
            Enum_Loc = Ident_1;
        }
        if (Enum_Loc == Ident_1) break;
    }
}

static void Proc_3(Rec_Pointer *Ptr_Ref_Par)
{
    if (Ptr_glob != 0)
        *Ptr_Ref_Par = Ptr_glob->Ptr_Comp;
    Proc_7(10, Int_glob, &Ptr_glob->variant.var_1.Int_Comp);
}

static void Proc_4(void)
{
    Boolean Bool_Loc = Ch_1_glob == 'A';
    Bool_glob = Bool_Loc | Bool_glob;
    Ch_2_glob = 'B';
}

static void Proc_5(void)
{
    Ch_1_glob = 'A';
    Bool_glob = FALSE;
}
