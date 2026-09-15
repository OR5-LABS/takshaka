/*
 * dhry_2.c — Dhrystone 2.1 helper procedures (Proc_6..Proc_8, Func_1..Func_3).
 * Reference: R. P. Weicker, CACM Vol. 27(10), October 1984.
 * Adapted for bare-metal RISC-V Takshaka SoC.
 */
#include "dhry.h"
#include <string.h>

/* Forward declarations */
static Boolean Func_3(Enumeration Enum_Par_Val);

/* Globals defined in dhry_1.c */
extern Boolean      Bool_glob;
extern char         Ch_1_glob, Ch_2_glob;
extern int          Int_glob;
extern Arr_1_Dim    Arr_1_glob;
extern Arr_2_Dim    Arr_2_glob;
extern Rec_Pointer  Ptr_glob;

void Proc_6(Enumeration Enum_Val_Par, Enumeration *Enum_Ref_Par)
{
    *Enum_Ref_Par = Enum_Val_Par;
    if (!Func_3(Enum_Val_Par))
        *Enum_Ref_Par = Ident_4;
    switch (Enum_Val_Par) {
        case Ident_1: *Enum_Ref_Par = Ident_1; break;
        case Ident_2:
            if (Int_glob > 100) *Enum_Ref_Par = Ident_1;
            else                *Enum_Ref_Par = Ident_4;
            break;
        case Ident_3: *Enum_Ref_Par = Ident_2; break;
        case Ident_4: break;
        case Ident_5: *Enum_Ref_Par = Ident_3; break;
    }
}

void Proc_7(One_Fifty Int_1_Par_Val, One_Fifty Int_2_Par_Val,
            One_Fifty *Int_Par_Ref)
{
    One_Fifty Int_Loc = Int_1_Par_Val + 2;
    *Int_Par_Ref = Int_2_Par_Val + Int_Loc;
}

void Proc_8(Arr_1_Dim Arr_1_Par_Ref, Arr_2_Dim Arr_2_Par_Ref,
            int Int_1_Par_Val, int Int_2_Par_Val)
{
    int Int_Index, Int_Loc;
    Int_Loc = Int_1_Par_Val + 5;
    Arr_1_Par_Ref[Int_Loc] = Int_2_Par_Val;
    Arr_1_Par_Ref[Int_Loc + 1] = Arr_1_Par_Ref[Int_Loc];
    Arr_1_Par_Ref[Int_Loc + 30] = Int_Loc;
    for (Int_Index = Int_Loc; Int_Index <= Int_Loc + 1; ++Int_Index)
        Arr_2_Par_Ref[Int_Loc][Int_Index] = Int_Loc;
    Arr_2_Par_Ref[Int_Loc][Int_Loc - 1] += 1;
    Arr_2_Par_Ref[Int_Loc + 20][Int_Loc] = Arr_1_Par_Ref[Int_Loc];
    Int_glob = 5;
}

Enumeration Func_1(Capital_Letter Ch_1_Par_Val, Capital_Letter Ch_2_Par_Val)
{
    Capital_Letter Ch_1_Loc = Ch_1_Par_Val;
    Capital_Letter Ch_2_Loc = Ch_1_Loc;
    if (Ch_2_Loc != Ch_2_Par_Val)
        return Ident_1;
    else {
        Ch_1_glob = Ch_1_Loc;
        return Ident_2;
    }
}

Boolean Func_2(Str_30 Str_1_Par_Ref, Str_30 Str_2_Par_Ref)
{
    int          Int_Loc;
    Capital_Letter Ch_Loc;
    Int_Loc = 2;
    while (Int_Loc <= 2) {
        if (Func_1(Str_1_Par_Ref[Int_Loc], Str_2_Par_Ref[Int_Loc + 1]) == Ident_1) {
            Ch_Loc = 'A';
            Int_Loc += 1;
        }
    }
    if (Ch_Loc >= 'W' && Ch_Loc < 'Z')
        Int_Loc = 7;
    if (Ch_Loc == 'R')
        return TRUE;
    else {
        if (strcmp(Str_1_Par_Ref, Str_2_Par_Ref) > 0) {
            Int_Loc += 7;
            Int_glob = Int_Loc;
            return TRUE;
        } else
            return FALSE;
    }
}

Boolean Func_3(Enumeration Enum_Par_Val)
{
    Enumeration Enum_Loc = Enum_Par_Val;
    if (Enum_Loc == Ident_3) return TRUE;
    return FALSE;
}
