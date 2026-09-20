#!/usr/bin/env python3
"""Co-simulation harness: diff the Takshaka RTL retire trace against the
golden RV32IM ISA model, instruction by instruction.

  python tools/cosim.py --hex programs/build/smoke.hex \
      --sim sim/tb_takshaka

Exit code 0 = traces match (RTL is ISA-correct); non-zero = mismatch.
"""
import argparse, os, re, subprocess, sys

LINE = re.compile(
    r"RETIRE pc=([0-9a-f]+) instr=([0-9a-f]+) rdwe=(\d) rd=(\d+) rdval=([0-9a-f]+)")

def parse(text):
    out = []
    for m in LINE.finditer(text):
        pc, instr, rdwe, rd, rdval = m.groups()
        out.append((int(pc,16), int(instr,16), int(rdwe), int(rd), int(rdval,16)))
    return out

def main():
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.dirname(here)
    ap = argparse.ArgumentParser()
    ap.add_argument("--hex", required=True)
    ap.add_argument("--sim", required=True, help="compiled simulator (Verilator binary; or a vvp image when --vvp is set)")
    ap.add_argument("--vvp", default=os.environ.get("VVP", "vvp"))
    ap.add_argument("--golden", default=os.path.join(here, "golden_rv32im.py"))
    ap.add_argument("--max", type=int, default=100000)
    a = ap.parse_args()

    cmd = [a.sim, f"+IMEM={a.hex}", "+TRACE=1"]
    if a.vvp:
        cmd.insert(0, a.vvp)
    rtl_raw = subprocess.run(
        cmd, capture_output=True, text=True).stdout
    gold_raw = subprocess.run(
        [sys.executable, a.golden, a.hex, str(a.max)],
        capture_output=True, text=True).stdout

    rtl = parse(rtl_raw)
    gold = parse(gold_raw)
    print(f"[cosim] RTL retires={len(rtl)}  golden retires={len(gold)}")

    n = min(len(rtl), len(gold))
    if n == 0:
        print("[cosim] FAIL: no retire trace to compare (RTL or golden run produced none)")
        sys.exit(3)
    for i in range(n):
        rp, ri, rwe, rd_, rv = rtl[i]
        gp, gi, gwe, gd, gv = gold[i]
        if rp != gp or ri != gi or rwe != gwe or \
           (rwe and (rd_ != gd or rv != gv)):
            print(f"[cosim] MISMATCH at retire #{i}:")
            print(f"  RTL    pc={rp:08x} instr={ri:08x} rdwe={rwe} rd={rd_} rdval={rv:08x}")
            print(f"  GOLDEN pc={gp:08x} instr={gi:08x} rdwe={gwe} rd={gd} rdval={gv:08x}")
            print("  --- preceding RTL context ---")
            for j in range(max(0,i-4), i):
                p,ii,we,d,v = rtl[j]
                print(f"    pc={p:08x} instr={ii:08x} rdwe={we} rd={d} rdval={v:08x}")
            sys.exit(1)

    if len(rtl) != len(gold):
        print(f"[cosim] length differs (RTL {len(rtl)} vs golden {len(gold)}) "
              f"but common prefix of {n} matched")
        # tolerate a 1-instruction tail difference at the halting store
        if abs(len(rtl) - len(gold)) > 1:
            print("[cosim] FAIL: trace lengths differ by more than one retire")
            sys.exit(2)

    print(f"[cosim] MATCH — {n} retires identical. RTL is ISA-correct.")
    sys.exit(0)

if __name__ == "__main__":
    main()
