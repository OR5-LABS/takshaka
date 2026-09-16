#!/usr/bin/env python3
# ==========================================================================
# run_rtos.py -- Self-checking Takshaka FreeRTOS demo harness.
#
# Runs the compiled FreeRTOS image (rtos.hex) on the Takshaka sim, captures
# the UART console transcript, and ASSERTS the observable RTOS behaviour:
#
#   1. Boot banner.
#   2. Producer/Consumer QUEUE: every value 1..NUM_ITEMS is sent by [P] and
#      received IN ORDER by [C]  ([P]send:N precedes its [C]got:N).
#   3. Counting SEMAPHORE: exactly NUM_ITEMS [C]sem takes, one per item.
#   4. PREEMPTION: the CPU-bound Worker task, which NEVER yields, still gets
#      [W]run@T lines -- it can only be scheduled off by the preemptive CLINT
#      timer tick, so any [W]run@ proves the tick preempted a running task.
#   5. Completion: [DONE]ok and tohost PASS.
#
# NEGATIVE CONTROL (rtos_neg.hex): the port's timer-setup is overridden to a
# no-op so mtimecmp stays at reset and the machine timer interrupt NEVER
# fires. With no tick, vTaskDelay() blocks forever: the demo must STALL after
# the first item and NEVER reach [DONE]ok. The harness asserts the neg run
# does NOT complete -- proving the preemptive tick is load-bearing.
#
# Usage:  python run_rtos.py            (build must have produced build/*.hex)
# Exit 0 = all assertions pass; non-zero = FAIL.
# ==========================================================================
import os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
CORE = os.path.dirname(HERE)                       # .../takshaka
G    = os.path.join(CORE, "..", "gandiva", "rtl")
DBG  = os.path.join(CORE, "..", "kavacha", "rtl", "kavacha_debug.sv")
SIM  = os.path.join(CORE, "sim", "tb_takshaka_rtos")
POS  = os.path.join(HERE, "build", "rtos.hex")
NEG  = os.path.join(HERE, "build", "rtos_neg.hex")

VERILATOR = os.environ.get("VERILATOR", "verilator")
NUM_ITEMS = 8

def sh(cmd, **kw):
    return subprocess.run(cmd, cwd=CORE, capture_output=True, text=True, **kw)

def compile_tb():
    src = [
        f"{G}/gandiva_pkg.sv", f"{G}/gandiva_alu.sv", f"{G}/gandiva_regfile.sv",
        f"{G}/gandiva_muldiv.sv", f"{G}/gandiva_csr.sv", f"{G}/gandiva_rvc.sv",
        f"{G}/gandiva_immgen.sv", f"{G}/gandiva_branch.sv", f"{G}/gandiva_decode.sv",
        DBG, "rtl/takshaka_core.sv", "rtl/takshaka_uart.sv", "rtl/takshaka_soc.sv",
        "tb/tb_takshaka_rtos.sv",
    ]
    cmd = [VERILATOR, "--binary", "-j", "0", "-Wno-fatal", "-Wno-WIDTHEXPAND", "-Wno-WIDTHTRUNC", "--trace", "--timescale", "1ns/1ps", "--Mdir", "sim", "-o", "tb_takshaka_rtos", "-I" + G, "-Irtl"] + src
    r = sh(cmd)
    if r.returncode != 0:
        print(r.stdout); print(r.stderr)
        sys.exit("COMPILE FAILED")
    print("[harness] testbench compiled")

def run(hexfile, maxcyc):
    r = sh([SIM, f"+IMEM={hexfile}", f"+MAXCYC={maxcyc}"])
    return r.stdout + r.stderr

def check_positive(t):
    errs = []
    lines = [l.strip() for l in t.splitlines()]

    if "[BOOT]freertos" not in lines:
        errs.append("missing [BOOT]freertos banner")

    sends = [int(m.group(1)) for l in lines
             for m in [re.match(r"\[P\]send:(\d+)$", l)] if m]
    gots  = [int(m.group(1)) for l in lines
             for m in [re.match(r"\[C\]got:(\d+)$", l)] if m]
    sems  = [l for l in lines if l == "[C]sem"]
    works = [int(m.group(1)) for l in lines
             for m in [re.match(r"\[W\]run@(\d+)$", l)] if m]

    exp = list(range(1, NUM_ITEMS + 1))
    if sends != exp:
        errs.append(f"queue SEND order wrong: got {sends}, want {exp}")
    if gots != exp:
        errs.append(f"queue RECV order wrong: got {gots}, want {exp}")
    if len(sems) != NUM_ITEMS:
        errs.append(f"semaphore takes = {len(sems)}, want {NUM_ITEMS}")

    # producer->consumer ordering: each send must appear before its recv
    for n in exp:
        try:
            si = lines.index(f"[P]send:{n}")
            gi = lines.index(f"[C]got:{n}")
            if not (si < gi):
                errs.append(f"item {n}: recv before send")
        except ValueError:
            errs.append(f"item {n}: send/recv line missing")

    # PREEMPTION witness: the non-yielding Worker only runs because the tick
    # preempted a task; each [W]run@T reports a FreeRTOS tick count > 0.
    if not works:
        errs.append("NO [W]run@ lines -> tick never preempted the Worker")
    elif not all(w > 0 for w in works):
        errs.append(f"[W] tick counts not positive: {works}")

    if "[DONE]ok" not in lines:
        errs.append("missing [DONE]ok")
    if "[TB] PASS" not in t:
        errs.append("sim did not report [TB] PASS (tohost!=1)")

    return errs, dict(sends=sends, gots=gots, sems=len(sems), works=works)

def check_negative(t):
    # With the tick disabled the demo MUST stall: it may print the boot banner,
    # the neg marker, and at most the first item -- but never completes.
    errs = []
    if "[NEG]tick-disabled" not in t:
        errs.append("neg build did not run the tick-disable override")
    if "[DONE]ok" in t:
        errs.append("NEG CONTROL reached [DONE]ok -- preemption NOT load-bearing!")
    if "[TB] PASS" in t:
        errs.append("NEG CONTROL reported PASS -- should stall, not complete")
    if "[TB] TIMEOUT" not in t:
        errs.append("NEG CONTROL did not hit the expected no-completion timeout")
    # It should not have progressed past the first produced item.
    n_got = len(re.findall(r"\[C\]got:\d+", t))
    if n_got > 1:
        errs.append(f"NEG CONTROL consumed {n_got} items -- expected <=1 (stall)")
    return errs, dict(consumed=n_got)

def main():
    if not (os.path.exists(POS) and os.path.exists(NEG)):
        sys.exit("build/rtos.hex or build/rtos_neg.hex missing -- run build_rtos.sh first")
    compile_tb()

    print("\n================ POSITIVE run (preemptive tick ON) ================")
    pos = run(POS, 2000000)
    print(pos)
    perr, pstat = check_positive(pos)

    print("================ NEGATIVE control (tick DISABLED) =================")
    # small budget: the neg run stalls immediately, no need for millions of cyc
    neg = run(NEG, 300000)
    print(neg)
    nerr, nstat = check_negative(neg)

    print("==================================================================")
    print(f"[positive] queue sends={pstat['sends']}")
    print(f"[positive] queue recvs={pstat['gots']}")
    print(f"[positive] semaphore takes={pstat['sems']}  worker preemption ticks={pstat['works']}")
    print(f"[negative] items consumed before stall={nstat['consumed']} (expect <=1)")

    ok = True
    if perr:
        ok = False
        print("\nPOSITIVE FAIL:")
        for e in perr: print("  -", e)
    else:
        print("\nPOSITIVE: PASS  (queue in-order 1..8, 8 semaphore takes, Worker preempted, [DONE]ok)")
    if nerr:
        ok = False
        print("NEGATIVE FAIL:")
        for e in nerr: print("  -", e)
    else:
        print("NEGATIVE: PASS  (tick disabled -> demo stalls, never completes)")

    print("\nRESULT:", "RTOS DEMO PASS" if ok else "RTOS DEMO FAIL")
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
