#!/usr/bin/env python3
"""Hand-assemble directed M/U-privilege + PMP tests for Takshaka SECURE=1.

Emits programs/build/priv_<name>.hex (one 32-bit word/line, for $readmemh).
Exit protocol (matches the family TB): store 1 -> PASS, 2 -> FAIL to tohost.

Each program is a self-checking directed test. The test index that FAILS is
written to tohost as (2 + idx) so a failing run pinpoints the sub-test.

Tests (each with a load-bearing NEGATIVE CONTROL):
  ustore : drop to U via mret, U store to a READ-ONLY PMP region -> store
           access-fault (mcause=7, mtval=addr); handler recovers. NEG CONTROL:
           same store to a R/W PMP region does NOT fault.
  ecall  : drop to U, U ecall -> trap mcause=8 (ecall-from-U). NEG CONTROL:
           an M-mode ecall traps with mcause=11 (ecall-from-M).
  ifetch : U-mode instruction fetch from a PMP no-exec region -> instruction
           access-fault (mcause=1, mtval=fetch pc). NEG CONTROL: fetching U
           code from an exec-permitted region runs and returns cleanly.
  ucsr   : U-mode read of an M-only CSR (mscratch) -> illegal instruction
           (mcause=2). NEG CONTROL: U-mode read of cycle (a U-readable CSR is
           not exercised here; instead the neg control is that in M-mode the
           same csrr succeeds), plus U-mode read of a non-priv op runs fine.
  uload  : U load from a PMP region without R -> load access-fault (mcause=5,
           mtval=addr, mepc=the load, rd unchanged). NEG CONTROL: with R set
           the load returns the data.
  mml_*  : Smepmp machine mode lockdown (mseccfg.MML). mml_mexec: M-mode
           execution from a U-only rule faults (mcause=1); mml_uload: a U load
           from an M-only (L=1) rule faults (mcause=5). NEG CONTROLS
           (mml_*_off): the same programs without MML follow the legacy rules
           and run. mml_cfg: pmpcfg/RLB write rules under MML, with controls.
  mtvec_mode : only direct mode is implemented, so mtvec.MODE reads as 0: a
           write of HANDLER|1 reads back as HANDLER and an ecall enters HANDLER.
  uamo   : U-mode AMOSWAP.W to a read-only PMP region -> store/AMO access-fault
           (mcause=7, mtval=addr, rd and memory unchanged). NEG CONTROL: with
           R/W the swap returns the old word and writes the new one.
"""
from pathlib import Path

def u32(x): return x & 0xFFFFFFFF
def R(f7, rs2, rs1, f3, rd, op): return u32((f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op)
def I(imm, rs1, f3, rd, op):     return u32(((imm&0xFFF)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op)
def S(imm, rs2, rs1, f3, op):
    imm &= 0xFFF
    return u32(((imm>>5)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((imm&0x1F)<<7)|op)
def B(imm, rs2, rs1, f3, op):
    imm &= 0x1FFE
    return u32(((imm>>12&1)<<31)|((imm>>5&0x3F)<<25)|(rs2<<20)|(rs1<<15)|
               (f3<<12)|((imm>>1&0xF)<<8)|((imm>>11&1)<<7)|op)
def U(imm, rd, op): return u32((imm&0xFFFFF000)|(rd<<7)|op)
def J(imm, rd, op):
    imm &= 0x1FFFFE
    return u32(((imm>>20&1)<<31)|((imm>>1&0x3FF)<<21)|((imm>>11&1)<<20)|
               ((imm>>12&0xFF)<<12)|(rd<<7)|op)

def addi(rd,rs1,i): return I(i,rs1,0,rd,0x13)
def add(rd,rs1,rs2):return R(0,rs2,rs1,0,rd,0x33)
def sub(rd,rs1,rs2):return R(0x20,rs2,rs1,0,rd,0x33)
def lui(rd,i):  return U(i,rd,0x37)
def lw(rd,rs1,i):  return I(i,rs1,2,rd,0x03)
def sw(rs2,rs1,i): return S(i,rs2,rs1,2,0x23)
def beq(rs1,rs2,i):return B(i,rs2,rs1,0,0x63)
def bne(rs1,rs2,i):return B(i,rs2,rs1,1,0x63)
def jal(rd,i):  return J(i,rd,0x6F)
def jalr(rd,rs1,i):return I(i,rs1,0,rd,0x67)
def csrrw(rd,csr,rs1): return I(csr,rs1,1,rd,0x73)
def csrrs(rd,csr,rs1): return I(csr,rs1,2,rd,0x73)
def csrrc(rd,csr,rs1): return I(csr,rs1,3,rd,0x73)
def csrrwi(rd,csr,imm):return I(csr,imm,5,rd,0x73)
def andi(rd,rs1,i): return I(i,rs1,7,rd,0x13)
def ecall():  return I(0,0,0,0,0x73)
def mret():   return I(0x302,0,0,0,0x73)
def nop():    return addi(0,0,0)

def li(rd, v):
    v &= 0xFFFFFFFF
    lo = v & 0xFFF
    hi = (v - (lo if lo < 0x800 else lo - 0x1000)) & 0xFFFFFFFF
    lo_s = lo if lo < 0x800 else lo - 0x1000
    if hi == 0:
        return [addi(rd, 0, lo_s)]
    return [lui(rd, hi), addi(rd, rd, lo_s)]

MSTATUS, MTVEC, MSCRATCH = 0x300, 0x305, 0x340
MEPC, MCAUSE, MTVAL = 0x341, 0x342, 0x343
PMPCFG0, PMPADDR0, PMPADDR1 = 0x3A0, 0x3B0, 0x3B1
TOHOST, DRAM = 0x20000000, 0x80000000

# PMP cfg byte fields
PMP_R, PMP_W, PMP_X = 0x01, 0x02, 0x04
PMP_TOR, PMP_NA4, PMP_NAPOT = 0x08, 0x10, 0x18
PMP_L = 0x80

OUT = Path(__file__).resolve().parent / "build"
OUT.mkdir(exist_ok=True)

def napot_addr(base, size):
    """Encode a NAPOT pmpaddr for [base, base+size). size is a power of 2 >= 8."""
    assert size >= 8 and (size & (size-1)) == 0
    return (base >> 2) | ((size >> 3) - 1)

# NAPOT encoding that matches the ENTIRE address space (pmpaddr all-ones ->
# match mask is 0, so every address matches). Used for the "catch-all" region
# that grants U-mode the baseline permissions outside the region under test.
NAPOT_ALL = 0xFFFFFFFF

def assemble(prog):
    if not prog: return []
    hi = max(prog) // 4
    words = [0x00000013] * (hi + 1)
    for a, w in prog.items():
        words[a//4] = w
    return words

def write_hex(name, prog):
    words = assemble(prog)
    p = OUT / f"priv_{name}.hex"
    p.write_text("".join(f"{w:08x}\n" for w in words))
    print(f"  wrote {p}  ({len(words)} words)")

# ============================================================================
# Common tohost helpers. We place the trap handler at a fixed high address in
# IMEM and the U-mode code at another fixed address, so PMP regions can target
# them precisely.
# ============================================================================
def pass_seq(base):
    # store 1 to tohost
    return { base+0: li(1,TOHOST)[0] if len(li(1,TOHOST))==1 else lui(1, (TOHOST) & 0xFFFFF000),
    }

# --------------------------------------------------------------------------
# Test 1: ustore — U store to a read-only PMP region faults (mcause=7).
#         Neg control: with the region R/W, the same store succeeds.
# --------------------------------------------------------------------------
def build_ustore(readonly):
    """readonly=True  -> region is R only  -> store must fault (mcause=7)
       readonly=False -> region is R/W     -> store must NOT fault (neg control)."""
    prog = {}
    def emit(addr, *ins):
        for x in ins:
            prog[addr] = x; addr += 4
        return addr

    HANDLER = 0x400
    UCODE   = 0x800
    # PMP region 0 covers a 64-byte NAPOT window at DRAM base.
    perm = PMP_R | (0 if readonly else PMP_W)
    cfg0 = PMP_NAPOT | perm
    # Region 1 = NAPOT catch-all (whole address space) R/W/X so U-mode can fetch
    # the handler + U code and access everything EXCEPT the region-0 window.
    # Region 0 is lower-numbered => wins for the restricted DRAM word.
    cfg1 = PMP_NAPOT | PMP_R | PMP_W | PMP_X

    pc = 0
    pc = emit(pc, *li(5, HANDLER), csrrw(0, MTVEC, 5))
    # program PMP: addr0 = NAPOT[DRAM, 64B], addr1 = NAPOT catch-all
    pc = emit(pc, *li(5, napot_addr(DRAM, 64)), csrrw(0, PMPADDR0, 5))
    pc = emit(pc, *li(5, NAPOT_ALL), csrrw(0, PMPADDR1, 5))
    pc = emit(pc, *li(5, (cfg1<<8)|cfg0), csrrw(0, PMPCFG0, 5))
    # x18 = 0 means "test not yet done"; handler sets x18=1 on the expected fault
    pc = emit(pc, addi(18,0,0))
    # set mstatus.MPP = U (00). Clear bits 12:11.
    pc = emit(pc, *li(5, 0x1800), csrrc(0, MSTATUS, 5))
    # mepc = UCODE ; mret drops to U
    pc = emit(pc, *li(5, UCODE), csrrw(0, MEPC, 5), mret())
    # (fallthrough should never execute)
    pc = emit(pc, jal(0,0))

    # ---- handler (M) ----
    h = HANDLER
    # read mcause -> x20, mtval -> x21
    h = emit(h, csrrs(20, MCAUSE, 0), csrrs(21, MTVAL, 0))
    if readonly:
        # expect store access-fault: mcause==7 and mtval==DRAM
        h = emit(h, addi(22,0,7), bne(20,22, 0))   # placeholder branch -> FAIL
        b_cause = h-4
        h = emit(h, *li(23, DRAM), bne(21,23, 0))  # mtval must equal fault addr
        b_tval = h-4
        # recovered: store 1 (PASS) to tohost
        h = emit(h, *li(1,TOHOST), addi(2,0,1), sw(2,1,0), jal(0,0))
        # FAIL blocks
        failc = h
        h = emit(h, *li(1,TOHOST), addi(2,0,3), sw(2,1,0), jal(0,0))  # code 3: wrong cause
        failt = h
        h = emit(h, *li(1,TOHOST), addi(2,0,4), sw(2,1,0), jal(0,0))  # code 4: wrong tval
        # fix branch targets
        prog[b_cause] = bne(20,22, failc - b_cause)
        prog[b_tval]  = bne(21,23, failt - b_tval)
    else:
        # neg control: a fault here is WRONG (store should have succeeded).
        h = emit(h, *li(1,TOHOST), addi(2,0,5), sw(2,1,0), jal(0,0))  # code 5: unexpected fault

    # ---- U code ----
    u = UCODE
    # store to the restricted word at DRAM+0
    u = emit(u, *li(6, DRAM), addi(7,0,0xAB), sw(7,6,0))
    if readonly:
        # if we get here the store did NOT fault -> WRONG
        u = emit(u, *li(1,TOHOST), addi(2,0,6), sw(2,1,0), jal(0,0))  # code 6: no fault
    else:
        # neg control success path: store worked. Read it back, verify, PASS.
        u = emit(u, lw(8,6,0), addi(9,0,0xAB), bne(8,9, 0))
        b_rb = u-4
        u = emit(u, *li(1,TOHOST), addi(2,0,1), sw(2,1,0), jal(0,0))  # PASS
        failrb = u
        u = emit(u, *li(1,TOHOST), addi(2,0,7), sw(2,1,0), jal(0,0))  # code 7: bad readback
        prog[b_rb] = bne(8,9, failrb - b_rb)
    return prog

# --------------------------------------------------------------------------
# Test 2: ecall — U ecall traps mcause=8; M ecall traps mcause=11 (neg ctrl).
# --------------------------------------------------------------------------
def build_ecall(from_user):
    prog = {}
    def emit(addr, *ins):
        for x in ins:
            prog[addr] = x; addr += 4
        return addr
    HANDLER = 0x400
    UCODE   = 0x800
    cfg = PMP_NAPOT | PMP_R | PMP_W | PMP_X      # region 0 = whole space RWX (U allowed)
    pc = 0
    pc = emit(pc, *li(5, HANDLER), csrrw(0, MTVEC, 5))
    pc = emit(pc, *li(5, NAPOT_ALL), csrrw(0, PMPADDR0, 5))
    pc = emit(pc, *li(5, cfg), csrrw(0, PMPCFG0, 5))
    if from_user:
        pc = emit(pc, *li(5, 0x1800), csrrc(0, MSTATUS, 5))  # MPP=U
        pc = emit(pc, *li(5, UCODE), csrrw(0, MEPC, 5), mret())
        pc = emit(pc, jal(0,0))
    else:
        # neg control: stay in M, ecall from M -> mcause 11
        pc = emit(pc, ecall())
        pc = emit(pc, jal(0,0))

    h = HANDLER
    h = emit(h, csrrs(20, MCAUSE, 0))
    want = 8 if from_user else 11
    h = emit(h, addi(22,0,want), bne(20,22, 0)); b = h-4
    h = emit(h, *li(1,TOHOST), addi(2,0,1), sw(2,1,0), jal(0,0))   # PASS
    fail = h
    h = emit(h, *li(1,TOHOST), addi(2,0,3), sw(2,1,0), jal(0,0))   # wrong cause
    prog[b] = bne(20,22, fail-b)

    u = UCODE
    u = emit(u, ecall())
    u = emit(u, jal(0,0))
    return prog

# --------------------------------------------------------------------------
# Test 3: ifetch — U fetch from a no-exec PMP region -> mcause=1 (mtval=pc).
#         Neg control: U fetch from an exec-permitted region runs and returns.
# --------------------------------------------------------------------------
def build_ifetch(noexec):
    prog = {}
    def emit(addr, *ins):
        for x in ins:
            prog[addr] = x; addr += 4
        return addr
    HANDLER = 0x400
    UCODE   = 0x800     # this NAPOT-64 window is the region under test
    # region 0: NAPOT 64B at UCODE. exec permission toggled by noexec.
    xperm = 0 if noexec else PMP_X
    cfg0 = PMP_NAPOT | PMP_R | xperm
    # region 1: NAPOT catch-all RWX so the handler + setup fetch fine and U can
    # read; region 0 (lower-numbered) governs exec of the UCODE window.
    cfg1 = PMP_NAPOT | PMP_R | PMP_W | PMP_X
    pc = 0
    pc = emit(pc, *li(5, HANDLER), csrrw(0, MTVEC, 5))
    pc = emit(pc, *li(5, napot_addr(UCODE, 64)), csrrw(0, PMPADDR0, 5))
    pc = emit(pc, *li(5, NAPOT_ALL), csrrw(0, PMPADDR1, 5))
    pc = emit(pc, *li(5, (cfg1<<8)|cfg0), csrrw(0, PMPCFG0, 5))
    pc = emit(pc, *li(5, 0x1800), csrrc(0, MSTATUS, 5))    # MPP=U
    pc = emit(pc, *li(5, UCODE), csrrw(0, MEPC, 5), mret())
    pc = emit(pc, jal(0,0))

    h = HANDLER
    h = emit(h, csrrs(20, MCAUSE, 0), csrrs(21, MTVAL, 0))
    if noexec:
        h = emit(h, addi(22,0,1), bne(20,22, 0)); bc = h-4     # instr access = 1
        h = emit(h, *li(23, UCODE), bne(21,23, 0)); bt = h-4   # mtval == fetch pc
        h = emit(h, *li(1,TOHOST), addi(2,0,1), sw(2,1,0), jal(0,0))  # PASS
        fc = h; h = emit(h, *li(1,TOHOST), addi(2,0,3), sw(2,1,0), jal(0,0))
        ft = h; h = emit(h, *li(1,TOHOST), addi(2,0,4), sw(2,1,0), jal(0,0))
        prog[bc] = bne(20,22, fc-bc); prog[bt] = bne(21,23, ft-bt)
    else:
        # neg control: a trap here is WRONG (U code was allowed to fetch+run).
        h = emit(h, *li(1,TOHOST), addi(2,0,5), sw(2,1,0), jal(0,0))  # code 5

    u = UCODE
    if noexec:
        # If we ever execute this, exec was wrongly allowed.
        u = emit(u, *li(1,TOHOST), addi(2,0,6), sw(2,1,0), jal(0,0))  # code 6
    else:
        # neg control success: run a couple of instrs then signal PASS from U.
        u = emit(u, addi(10,0,1), addi(11,0,2), add(12,10,11), addi(13,0,3))
        u = emit(u, bne(12,13, 0)); bb = u-4
        u = emit(u, *li(1,TOHOST), addi(2,0,1), sw(2,1,0), jal(0,0))  # PASS
        fb = u; u = emit(u, *li(1,TOHOST), addi(2,0,7), sw(2,1,0), jal(0,0))
        prog[bb] = bne(12,13, fb-bb)
    return prog

# --------------------------------------------------------------------------
# Test 4: ucsr — U read of M-only CSR (mscratch) -> illegal (mcause=2).
#         Neg control: the SAME csrr in M-mode succeeds (no trap).
# --------------------------------------------------------------------------
def build_ucsr(from_user):
    prog = {}
    def emit(addr, *ins):
        for x in ins:
            prog[addr] = x; addr += 4
        return addr
    HANDLER = 0x400
    UCODE   = 0x800
    cfg = PMP_NAPOT | PMP_R | PMP_W | PMP_X
    pc = 0
    pc = emit(pc, *li(5, HANDLER), csrrw(0, MTVEC, 5))
    pc = emit(pc, *li(5, NAPOT_ALL), csrrw(0, PMPADDR0, 5))
    pc = emit(pc, *li(5, cfg), csrrw(0, PMPCFG0, 5))
    # seed mscratch with a known value so the M-mode neg control can verify it.
    pc = emit(pc, *li(5, 0x5A5A1234), csrrw(0, MSCRATCH, 5))
    if from_user:
        pc = emit(pc, *li(5, 0x1800), csrrc(0, MSTATUS, 5))
        pc = emit(pc, *li(5, UCODE), csrrw(0, MEPC, 5), mret())
        pc = emit(pc, jal(0,0))
    else:
        # neg control: read mscratch in M-mode -> must succeed, value matches.
        pc = emit(pc, csrrs(10, MSCRATCH, 0), *li(11,0x5A5A1234), bne(10,11, 0)); b=pc-4
        pc = emit(pc, *li(1,TOHOST), addi(2,0,1), sw(2,1,0), jal(0,0))  # PASS
        f = pc; pc = emit(pc, *li(1,TOHOST), addi(2,0,8), sw(2,1,0), jal(0,0))
        prog[b] = bne(10,11, f-b)

    h = HANDLER
    h = emit(h, csrrs(20, MCAUSE, 0))
    h = emit(h, addi(22,0,2), bne(20,22, 0)); bc = h-4    # illegal instr = 2
    h = emit(h, *li(1,TOHOST), addi(2,0,1), sw(2,1,0), jal(0,0))  # PASS
    fc = h; h = emit(h, *li(1,TOHOST), addi(2,0,3), sw(2,1,0), jal(0,0))
    prog[bc] = bne(20,22, fc-bc)

    u = UCODE
    u = emit(u, csrrs(10, MSCRATCH, 0))   # illegal in U -> trap
    u = emit(u, *li(1,TOHOST), addi(2,0,9), sw(2,1,0), jal(0,0))  # code 9 (no trap)
    return prog

# --------------------------------------------------------------------------
# Test 5: uload — U load from a PMP region with no read permission -> load
#         access-fault (mcause=5, mtval=addr, mepc=the load). The trap must be
#         taken (the load is not skipped) and rd must keep its old value.
#         Neg control: with R set, the same load succeeds and returns the data.
# --------------------------------------------------------------------------
PMPCFG1 = 0x3A1
PMPADDR2, PMPADDR3 = 0x3B2, 0x3B3
MSECCFG = 0x747

def tohost_code(emit, at, code):
    return emit(at, *li(1,TOHOST), addi(2,0,code), sw(2,1,0), jal(0,0))

def build_uload(noread):
    prog = {}
    def emit(addr, *ins):
        for x in ins:
            prog[addr] = x; addr += 4
        return addr
    HANDLER = 0x400
    UCODE   = 0x800
    cfg0 = PMP_NAPOT | (0 if noread else PMP_R)      # DRAM window under test
    cfg1 = PMP_NAPOT | PMP_R | PMP_W | PMP_X         # catch-all
    pc = 0
    pc = emit(pc, *li(5, HANDLER), csrrw(0, MTVEC, 5))
    # seed the DRAM word so the neg control can check the loaded value
    pc = emit(pc, *li(6, DRAM), *li(7, 0x600DF00D), sw(7,6,0))
    pc = emit(pc, *li(5, napot_addr(DRAM, 64)), csrrw(0, PMPADDR0, 5))
    pc = emit(pc, *li(5, NAPOT_ALL), csrrw(0, PMPADDR1, 5))
    pc = emit(pc, *li(5, (cfg1<<8)|cfg0), csrrw(0, PMPCFG0, 5))
    pc = emit(pc, *li(8, 0x1234))                    # rd of the load: old value
    pc = emit(pc, *li(5, 0x1800), csrrc(0, MSTATUS, 5))        # MPP=U
    pc = emit(pc, *li(5, UCODE), csrrw(0, MEPC, 5), mret())
    pc = emit(pc, jal(0,0))

    u = UCODE
    u = emit(u, *li(6, DRAM))
    load_pc = u
    u = emit(u, lw(8,6,0))
    if noread:
        u = tohost_code(emit, u, 6)                  # code 6: load did not trap
    else:
        u = emit(u, *li(9, 0x600DF00D), bne(8,9, 0)); b = u-4
        u = tohost_code(emit, u, 1)                  # PASS
        f = u; u = tohost_code(emit, u, 7)           # code 7: wrong data
        prog[b] = bne(8,9, f-b)

    h = HANDLER
    if noread:
        h = emit(h, csrrs(20, MCAUSE, 0), addi(22,0,5), bne(20,22, 0)); bc = h-4
        h = emit(h, csrrs(21, MTVAL, 0), *li(23, DRAM), bne(21,23, 0)); bt = h-4
        h = emit(h, csrrs(24, MEPC, 0), *li(25, load_pc), bne(24,25, 0)); be = h-4
        h = emit(h, *li(26, 0x1234), bne(8,26, 0)); br = h-4
        h = tohost_code(emit, h, 1)                  # PASS
        fc = h; h = tohost_code(emit, h, 3)          # wrong mcause
        ft = h; h = tohost_code(emit, h, 4)          # wrong mtval
        fe = h; h = tohost_code(emit, h, 8)          # wrong mepc
        fr = h; h = tohost_code(emit, h, 9)          # rd was written
        prog[bc] = bne(20,22, fc-bc); prog[bt] = bne(21,23, ft-bt)
        prog[be] = bne(24,25, fe-be); prog[br] = bne(8,26, fr-br)
    else:
        h = tohost_code(emit, h, 5)                  # code 5: unexpected trap
    return prog

# --------------------------------------------------------------------------
# Smepmp machine mode lockdown (mseccfg.MML, Smepmp 1.0).
#
# Shared PMP layout (rules valid both before and after MML is set):
#   region 0  DRAM[0..63]     L=1 R W   (MML: M-only RW;  legacy: M+U RW)
#   region 1  UCODE[0..63]    L=0 R X   (MML: U-only RX;  legacy: U RX, M any)
#   region 2  0x0..0xFFF      L=1 R X   (MML: M-only RX;  legacy: M+U RX)
#   region 3  everything      L=0 W X   (MML: shared RW (Smepmp LRWX=0011);
#                                        legacy: U W X, M any)
# --------------------------------------------------------------------------
MML_CFG = ((PMP_NAPOT|PMP_W|PMP_X) << 24) | ((PMP_L|PMP_NAPOT|PMP_R|PMP_X) << 16) | \
          ((PMP_NAPOT|PMP_R|PMP_X) << 8) | (PMP_L|PMP_NAPOT|PMP_R|PMP_W)

def mml_setup(emit, pc, handler, ucode, set_mml):
    pc = emit(pc, *li(5, handler), csrrw(0, MTVEC, 5))
    pc = emit(pc, *li(5, napot_addr(DRAM, 64)),    csrrw(0, PMPADDR0, 5))
    pc = emit(pc, *li(5, napot_addr(ucode, 64)),   csrrw(0, PMPADDR1, 5))
    pc = emit(pc, *li(5, napot_addr(0, 0x1000)),   csrrw(0, PMPADDR2, 5))
    pc = emit(pc, *li(5, NAPOT_ALL),               csrrw(0, PMPADDR3, 5))
    pc = emit(pc, *li(5, MML_CFG),                 csrrw(0, PMPCFG0, 5))
    if set_mml:
        pc = emit(pc, csrrwi(0, MSECCFG, 1))         # mseccfg.MML = 1
    return pc

# mml_mexec: with MML=1, M-mode may not execute from a U-only (L=0) rule ->
#   instruction access-fault (mcause=1, mtval=target). Neg control (MML=0):
#   the same jump executes the code there (legacy: M ignores L=0 rules).
def build_mml_mexec(set_mml):
    prog = {}
    def emit(addr, *ins):
        for x in ins:
            prog[addr] = x; addr += 4
        return addr
    HANDLER, UCODE = 0x400, 0x800
    pc = mml_setup(emit, 0, HANDLER, UCODE, set_mml)
    pc = emit(pc, jal(0, UCODE - pc))               # M jumps into the U-only window

    u = UCODE
    u = tohost_code(emit, u, 6 if set_mml else 1)   # MML: code 6 (M executed) / off: PASS

    h = HANDLER
    if set_mml:
        h = emit(h, csrrs(20, MCAUSE, 0), addi(22,0,1), bne(20,22, 0)); bc = h-4
        h = emit(h, csrrs(21, MTVAL, 0), *li(23, UCODE), bne(21,23, 0)); bt = h-4
        h = tohost_code(emit, h, 1)                  # PASS
        fc = h; h = tohost_code(emit, h, 3)
        ft = h; h = tohost_code(emit, h, 4)
        prog[bc] = bne(20,22, fc-bc); prog[bt] = bne(21,23, ft-bt)
    else:
        h = tohost_code(emit, h, 5)                  # unexpected trap
    return prog

# mml_uload: with MML=1, an L=1 rule is M-only, so a U load from it faults
#   (mcause=5, mtval=addr, rd unchanged). Neg control (MML=0): the legacy L=1
#   R/W rule also grants U, so the load succeeds.
def build_mml_uload(set_mml):
    prog = {}
    def emit(addr, *ins):
        for x in ins:
            prog[addr] = x; addr += 4
        return addr
    HANDLER, UCODE = 0x400, 0x800
    pc = 0
    pc = emit(pc, *li(6, DRAM), *li(7, 0x600DF00D), sw(7,6,0))
    pc = mml_setup(emit, pc, HANDLER, UCODE, set_mml)
    pc = emit(pc, *li(8, 0x1234))
    pc = emit(pc, *li(5, 0x1800), csrrc(0, MSTATUS, 5))        # MPP=U
    pc = emit(pc, *li(5, UCODE), csrrw(0, MEPC, 5), mret())
    pc = emit(pc, jal(0,0))

    u = UCODE
    u = emit(u, *li(6, DRAM), lw(8,6,0))
    if set_mml:
        u = tohost_code(emit, u, 6)                  # code 6: U read an M-only rule
    else:
        u = emit(u, *li(9, 0x600DF00D), bne(8,9, 0)); b = u-4
        u = tohost_code(emit, u, 1)                  # PASS
        f = u; u = tohost_code(emit, u, 7)
        prog[b] = bne(8,9, f-b)

    h = HANDLER
    if set_mml:
        h = emit(h, csrrs(20, MCAUSE, 0), addi(22,0,5), bne(20,22, 0)); bc = h-4
        h = emit(h, csrrs(21, MTVAL, 0), *li(23, DRAM), bne(21,23, 0)); bt = h-4
        h = emit(h, *li(26, 0x1234), bne(8,26, 0)); br = h-4
        h = tohost_code(emit, h, 1)                  # PASS
        fc = h; h = tohost_code(emit, h, 3)
        ft = h; h = tohost_code(emit, h, 4)
        fr = h; h = tohost_code(emit, h, 9)
        prog[bc] = bne(20,22, fc-bc); prog[bt] = bne(21,23, ft-bt)
        prog[br] = bne(8,26, fr-br)
    else:
        h = tohost_code(emit, h, 5)
    return prog

# mml_cfg: Smepmp CSR write rules.
#   * RLB can be set while no rule is locked (control), and cleared again.
#   * With MML=1 and RLB=0, a pmpcfg write that adds an executable M-only rule
#     (L=1 X=1 W=0) or a locked shared-code rule (L=1 R=0 W=1) is ignored,
#     while an ordinary rule (L=0 R W) is still written (control).
#   * With RLB=0 and a locked rule present, RLB cannot be set.
def build_mml_cfg():
    prog = {}
    def emit(addr, *ins):
        for x in ins:
            prog[addr] = x; addr += 4
        return addr
    HANDLER, UCODE = 0x400, 0x800
    br = []
    pc = 0
    # RLB settable with no locked rule (read back bit 2), then clear it
    pc = emit(pc, csrrwi(0, MSECCFG, 4), csrrs(10, MSECCFG, 0), andi(10,10,4),
              addi(11,0,4), bne(10,11, 0)); br.append((pc-4, 10, 11, 7))
    pc = emit(pc, csrrwi(0, MSECCFG, 0))
    pc = mml_setup(emit, pc, HANDLER, UCODE, True)
    # executable M-only rule in pmp4cfg -> ignored
    pc = emit(pc, *li(5, PMP_L|PMP_NAPOT|PMP_X), csrrw(0, PMPCFG1, 5),
              csrrs(10, PMPCFG1, 0), bne(10,0, 0)); br.append((pc-4, 10, 0, 3))
    # locked shared-code rule in pmp4cfg -> ignored
    pc = emit(pc, *li(5, PMP_L|PMP_NAPOT|PMP_W), csrrw(0, PMPCFG1, 5),
              csrrs(10, PMPCFG1, 0), bne(10,0, 0)); br.append((pc-4, 10, 0, 4))
    # ordinary rule -> written
    pc = emit(pc, *li(5, PMP_NAPOT|PMP_R|PMP_W), csrrw(0, PMPCFG1, 5),
              csrrs(10, PMPCFG1, 0), *li(11, PMP_NAPOT|PMP_R|PMP_W), bne(10,11, 0))
    br.append((pc-4, 10, 11, 5))
    # RLB with locked rules present -> stays 0
    pc = emit(pc, csrrwi(0, MSECCFG, 5), csrrs(10, MSECCFG, 0), andi(10,10,4),
              bne(10,0, 0)); br.append((pc-4, 10, 0, 6))
    pc = tohost_code(emit, pc, 1)                    # PASS
    for (at, ra, rb, code) in br:
        f = pc; pc = tohost_code(emit, pc, code)
        prog[at] = bne(ra, rb, f-at)
    h = HANDLER
    h = tohost_code(emit, h, 8)                      # no trap expected
    return prog

# uamo: U-mode AMOSWAP.W to a read-only PMP region -> store/AMO access-fault
#   (mcause=7, mtval=addr); rd and memory unchanged. Neg control: with R/W the
#   swap returns the old word and stores the new one.
def amoswap_w(rd, rs2, rs1): return R(0x04, rs2, rs1, 2, rd, 0x2F)

def build_uamo(readonly):
    prog = {}
    def emit(addr, *ins):
        for x in ins:
            prog[addr] = x; addr += 4
        return addr
    HANDLER, UCODE = 0x400, 0x800
    cfg0 = PMP_NAPOT | PMP_R | (0 if readonly else PMP_W)
    cfg1 = PMP_NAPOT | PMP_R | PMP_W | PMP_X
    pc = 0
    pc = emit(pc, *li(5, HANDLER), csrrw(0, MTVEC, 5))
    pc = emit(pc, *li(6, DRAM), *li(7, 0x600DF00D), sw(7,6,0))
    pc = emit(pc, *li(5, napot_addr(DRAM, 64)), csrrw(0, PMPADDR0, 5))
    pc = emit(pc, *li(5, NAPOT_ALL), csrrw(0, PMPADDR1, 5))
    pc = emit(pc, *li(5, (cfg1<<8)|cfg0), csrrw(0, PMPCFG0, 5))
    pc = emit(pc, *li(8, 0x1234))
    pc = emit(pc, *li(5, 0x1800), csrrc(0, MSTATUS, 5))        # MPP=U
    pc = emit(pc, *li(5, UCODE), csrrw(0, MEPC, 5), mret())
    pc = emit(pc, jal(0,0))

    u = UCODE
    u = emit(u, *li(6, DRAM), *li(9, 0x0BADCAFE), amoswap_w(8, 9, 6))
    if readonly:
        u = tohost_code(emit, u, 6)                  # code 6: AMO did not trap
    else:
        u = emit(u, *li(10, 0x600DF00D), bne(8,10, 0)); b1 = u-4
        u = emit(u, lw(11,6,0), bne(11,9, 0)); b2 = u-4
        u = tohost_code(emit, u, 1)                  # PASS
        f1 = u; u = tohost_code(emit, u, 7)          # code 7: wrong old value
        f2 = u; u = tohost_code(emit, u, 8)          # code 8: memory not written
        prog[b1] = bne(8,10, f1-b1); prog[b2] = bne(11,9, f2-b2)

    h = HANDLER
    if readonly:
        h = emit(h, csrrs(20, MCAUSE, 0), addi(22,0,7), bne(20,22, 0)); bc = h-4
        h = emit(h, csrrs(21, MTVAL, 0), *li(23, DRAM), bne(21,23, 0)); bt = h-4
        h = emit(h, *li(26, 0x1234), bne(8,26, 0)); br = h-4
        h = emit(h, *li(6, DRAM), lw(11,6,0), *li(27, 0x600DF00D), bne(11,27, 0)); bm = h-4
        h = tohost_code(emit, h, 1)                  # PASS
        fc = h; h = tohost_code(emit, h, 3)          # wrong mcause
        ft = h; h = tohost_code(emit, h, 4)          # wrong mtval
        fr = h; h = tohost_code(emit, h, 9)          # rd was written
        fm = h; h = tohost_code(emit, h, 10)         # memory was written
        prog[bc] = bne(20,22, fc-bc); prog[bt] = bne(21,23, ft-bt)
        prog[br] = bne(8,26, fr-br);  prog[bm] = bne(11,27, fm-bm)
    else:
        h = tohost_code(emit, h, 5)                  # unexpected trap
    return prog

# mtvec_mode: only direct mode is implemented, so mtvec.MODE is WARL 0: a write
#   of HANDLER|1 must read back as HANDLER, and an ecall must enter HANDLER.
def build_mtvec_mode():
    prog = {}
    def emit(addr, *ins):
        for x in ins:
            prog[addr] = x; addr += 4
        return addr
    HANDLER = 0x400
    pc = 0
    pc = emit(pc, *li(5, HANDLER | 1), csrrw(0, MTVEC, 5), csrrs(10, MTVEC, 0),
              *li(11, HANDLER), bne(10,11, 0)); b = pc-4
    pc = emit(pc, ecall())
    pc = tohost_code(emit, pc, 4)                    # code 4: ecall did not trap
    f = pc; pc = tohost_code(emit, pc, 3)            # code 3: MODE bits read back
    prog[b] = bne(10,11, f-b)
    h = HANDLER
    h = emit(h, csrrs(20, MCAUSE, 0), addi(22,0,11), bne(20,22, 0)); bc = h-4
    h = tohost_code(emit, h, 1)                      # PASS
    fc = h; h = tohost_code(emit, h, 5)              # code 5: wrong mcause
    prog[bc] = bne(20,22, fc-bc)
    return prog

if __name__ == "__main__":
    write_hex("ustore_fault", build_ustore(readonly=True))
    write_hex("ustore_ok",    build_ustore(readonly=False))
    write_hex("ecall_u",      build_ecall(from_user=True))
    write_hex("ecall_m",      build_ecall(from_user=False))
    write_hex("ifetch_fault", build_ifetch(noexec=True))
    write_hex("ifetch_ok",    build_ifetch(noexec=False))
    write_hex("ucsr_u",       build_ucsr(from_user=True))
    write_hex("ucsr_m",       build_ucsr(from_user=False))
    write_hex("uload_fault",  build_uload(noread=True))
    write_hex("uload_ok",     build_uload(noread=False))
    write_hex("mml_mexec",    build_mml_mexec(set_mml=True))
    write_hex("mml_mexec_off",build_mml_mexec(set_mml=False))
    write_hex("mml_uload",    build_mml_uload(set_mml=True))
    write_hex("mml_uload_off",build_mml_uload(set_mml=False))
    write_hex("mml_cfg",      build_mml_cfg())
    write_hex("mtvec_mode",   build_mtvec_mode())
    write_hex("uamo_fault",   build_uamo(readonly=True))
    write_hex("uamo_ok",      build_uamo(readonly=False))
    print("done.")
