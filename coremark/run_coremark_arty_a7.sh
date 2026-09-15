#!/usr/bin/env bash
# =============================================================================
# run_coremark_arty_a7.sh — Build CoreMark, synthesize for the Digilent 
# Arty A7-100T via Vivado, program the board, and capture CoreMark results.
#
# Usage:
#   ./run_coremark_arty_a7.sh [OPTIONS]
#
# Options:
#   --runs N          Number of CoreMark iterations   (default: 10000)
#   --build-dir DIR   Vivado build output directory   (default: ../fpga/arty_a7/build)
#   --no-synth        Skip re-synthesis; use existing bitstream
#   --no-program      Skip board programming (just build)
#   --programmer TOOL Programmer: openFPGALoader | vivado  (default: auto-detect)
#   --uart-dev DEV    UART device for result capture  (default: /dev/ttyUSB1)
#   --baud RATE       UART baud rate                  (default: 115200)
#   --timeout SECS    Seconds to wait for UART output (default: 300)
#
# Prerequisites:
#   - RISC-V GCC toolchain (riscv-none-elf-gcc) in PATH or $RISCV_TC
#   - Vivado in PATH (for --no-synth=false, the default)
#   - openFPGALoader in PATH -OR- Vivado HW manager (for programming)
#   - pyserial  (pip install pyserial)  for UART capture
#
# Board connections:
#   CLK  : E3  (100 MHz onboard oscillator)
#   RST  : C2  (ck_rst, active-low pushbutton)
#   UART : A9  (RX into board) / D10 (TX out of board) — 115200-8N1
#   JTAG : USB-JTAG on the micro-USB port (FTDI FT2232H)
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---- Defaults ---------------------------------------------------------------
RUNS=10000
BUILD_DIR="$REPO_ROOT/fpga/arty_a7/build"
DO_SYNTH=1
DO_PROGRAM=1
PROGRAMMER=auto
UART_DEV=/dev/ttyUSB1
BAUD=115200
TIMEOUT=300

# FPGA clock frequency
CLK_HZ=25000000           # 25 MHz (divided from 100MHz)
PART=xc7a100tcsg324-1
TCL_SCRIPT="$REPO_ROOT/fpga/arty_a7/takshaka_arty_a7.tcl"

# ---- Parse arguments --------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --runs)       RUNS="$2";       shift 2 ;;
        --build-dir)  BUILD_DIR="$2";  shift 2 ;;
        --no-synth)   DO_SYNTH=0;      shift   ;;
        --no-program) DO_PROGRAM=0;    shift   ;;
        --programmer) PROGRAMMER="$2"; shift 2 ;;
        --uart-dev)   UART_DEV="$2";   shift 2 ;;
        --baud)       BAUD="$2";       shift 2 ;;
        --timeout)    TIMEOUT="$2";    shift 2 ;;
        -h|--help)
            sed -n '3,27p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# ---- Colour helpers ---------------------------------------------------------
RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'
BLU='\033[0;34m'; CYN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${BLU}[INFO]${NC}  $*"; }
ok()    { echo -e "${GRN}[OK]${NC}    $*"; }
warn()  { echo -e "${YLW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
sep()   { echo -e "${CYN}$(printf '%.0s─' {1..72})${NC}"; }

sep
echo -e "${CYN}  Takshaka CoreMark — Arty A7-100T FPGA Run${NC}"
echo -e "  Iterations : ${YLW}${RUNS}${NC}"
echo -e "  Clock      : ${YLW}${CLK_HZ} Hz${NC}  (100 MHz)"
echo -e "  UART       : ${UART_DEV}  @ ${BAUD}-8N1"
sep

# =============================================================================
# STEP 1 — Toolchain detection
# =============================================================================
info "Detecting RISC-V toolchain..."
TC="${RISCV_TC:-/home/yash/toolchains/xpack-riscv-none-elf-gcc-13.2.0-2/bin}"
GCC="${GCC:-$TC/riscv-none-elf-gcc}"
OBJCOPY="${OBJCOPY:-$TC/riscv-none-elf-objcopy}"

if ! command -v "$GCC" &>/dev/null; then
    if   command -v riscv-none-elf-gcc      &>/dev/null; then
        GCC=riscv-none-elf-gcc; OBJCOPY=riscv-none-elf-objcopy
    elif command -v riscv32-unknown-elf-gcc &>/dev/null; then
        GCC=riscv32-unknown-elf-gcc; OBJCOPY=riscv32-unknown-elf-objcopy
    else
        die "RISC-V GCC toolchain not found. Set RISCV_TC or GCC env vars."
    fi
fi
ok "Using GCC: $(command -v "$GCC")"

# =============================================================================
# STEP 2 — Compile CoreMark firmware for Arty A7 (25 MHz clock)
# =============================================================================
sep
info "Compiling CoreMark (${RUNS} iterations, CLK=${CLK_HZ} Hz)..."
SRC_DIR="$SCRIPT_DIR/src"
LDSCRIPT="$SRC_DIR/../link_fpga.ld"   # unified BRAM

# create a temporary link_fpga.ld inside coremark/ if it doesn't exist
if [[ ! -f "$LDSCRIPT" ]]; then
    # copy from dhrystone which has it
    cp "$REPO_ROOT/dhrystone/src/link_fpga.ld" "$LDSCRIPT"
fi

FLAGS="-O2 -march=rv32im -mabi=ilp32 -nostartfiles -fno-pic -Wl,--no-relax -fno-builtin"
INCLUDES="-I$SRC_DIR"

"$GCC" $FLAGS $INCLUDES -T "$LDSCRIPT" \
    -DITERATIONS=$RUNS -DFLAGS_STR="\"$FLAGS\"" \
    -DPERFORMANCE_RUN=1 \
    -DMAIN_HAS_NOARGC=1 \
    -DEE_TICKS_PER_SEC="${CLK_HZ}UL" \
    -DMEM_METHOD=MEM_STATIC \
    -DSEED_METHOD=SEED_VOLATILE \
    -DHAS_FLOAT=0 \
    -DHAS_TIME_H=0 \
    -DUSE_CLOCK=0 \
    -DHAS_STDIO=0 \
    -DHAS_PRINTF=0 \
    -DMULTITHREAD=1 \
    -DUSE_PTHREAD=0 \
    "$REPO_ROOT/dhrystone/src/start.S" \
    "$SRC_DIR/core_portme.c" \
    "$SRC_DIR/core_list_join.c" \
    "$SRC_DIR/core_main.c" \
    "$SRC_DIR/core_matrix.c" \
    "$SRC_DIR/core_state.c" \
    "$SRC_DIR/core_util.c" \
    -o "$SRC_DIR/coremark_arty.elf"

ok "ELF built: $SRC_DIR/coremark_arty.elf"

# ---- Convert ELF → binary → firmware.mem ($readmemh, one word per line) -----
"$OBJCOPY" -O binary "$SRC_DIR/coremark_arty.elf" "$SRC_DIR/coremark_arty.bin"
MEM_FILE="$BUILD_DIR/firmware.mem"
mkdir -p "$BUILD_DIR"
python3 "$REPO_ROOT/sw/bin2hex.py" "$SRC_DIR/coremark_arty.bin" "$MEM_FILE"
ok "firmware.mem written: $MEM_FILE"

# =============================================================================
# STEP 3 — Vivado synthesis / P&R (optional, skipped with --no-synth)
# =============================================================================
BITFILE="$BUILD_DIR/takshaka_arty_a7.bit"

if [[ $DO_SYNTH -eq 1 ]]; then
    sep
    info "Running Vivado synthesis + implementation for ${PART}..."
    if ! command -v vivado &>/dev/null; then
        die "vivado not found in PATH. Source Vivado settings64.sh or use --no-synth."
    fi
    vivado -mode batch \
           -source "$TCL_SCRIPT" \
           -tclargs "$BUILD_DIR" \
           -log "$BUILD_DIR/vivado_coremark.log" \
           -journal "$BUILD_DIR/vivado_coremark.jou"
    ok "Bitstream ready: $BITFILE"
else
    warn "--no-synth: skipping full synthesis."
    if [[ -f "$BUILD_DIR/route.dcp" ]]; then
        info "Running fast re-bitstream to update BRAM with new firmware..."
        cat << 'EOF' > "$BUILD_DIR/fast_rebit.tcl"
set build_dir [lindex $argv 0]
open_checkpoint "$build_dir/route.dcp"
add_files -norecurse "$build_dir/firmware.mem"
set_property file_type {Memory Initialization Files} [get_files firmware.mem]
write_bitstream -force "$build_dir/takshaka_arty_a7.bit"
EOF
        vivado -mode batch -source "$BUILD_DIR/fast_rebit.tcl" -tclargs "$BUILD_DIR" \
               -log "$BUILD_DIR/vivado_rebit.log" -journal "$BUILD_DIR/vivado_rebit.jou"
        ok "Bitstream updated via fast re-bit: $BITFILE"
    else
        warn "No route.dcp found for fast re-bit. Using existing bitstream unmodified."
        [[ -f "$BITFILE" ]] || die "No existing bitstream at $BITFILE. Remove --no-synth to build one."
        ok "Using existing bitstream: $BITFILE"
    fi
fi

# =============================================================================
# STEP 4 — Auto-detect UART device (if default not present)
# =============================================================================
sep
if [[ ! -e "$UART_DEV" ]]; then
    warn "${UART_DEV} not found — scanning for ttyUSB devices..."
    # FT2232H on Arty A7: ttyUSB0=JTAG, ttyUSB1=UART; pick the highest index
    mapfile -t usb_ttys < <(ls /dev/ttyUSB* 2>/dev/null | sort)
    if [[ ${#usb_ttys[@]} -eq 0 ]]; then
        die "No /dev/ttyUSB* devices found. Is the Arty A7 connected?"
    fi
    UART_DEV="${usb_ttys[-1]}"
    warn "Using ${UART_DEV} (override with --uart-dev if wrong)"
fi
info "UART device : ${UART_DEV} @ ${BAUD}-8N1  (timeout ${TIMEOUT}s)"

# =============================================================================
# STEP 5 — Start UART listener IN BACKGROUND *before* programming the board
# =============================================================================
UART_LOG="$(mktemp /tmp/takshaka_coremark_uart.XXXXXX)"
UART_DONE_FLAG="$(mktemp /tmp/takshaka_coremark_done.XXXXXX)"
rm -f "$UART_DONE_FLAG"

if python3 -c "import serial" 2>/dev/null; then
    info "Starting background UART listener (pyserial)..."
    python3 - "$UART_DEV" "$BAUD" "$TIMEOUT" "$UART_LOG" "$UART_DONE_FLAG" <<'PYEOF' &
import serial, sys, time, os

dev        = sys.argv[1]
baud       = int(sys.argv[2])
tmax       = int(sys.argv[3])
log_path   = sys.argv[4]
done_flag  = sys.argv[5]

found_result = False
t0 = time.time()
buf = b""

with open(log_path, "wb") as fout:
    while time.time() - t0 < tmax:
        try:
            with serial.Serial(dev, baud, timeout=1) as ser:
                while time.time() - t0 < tmax:
                    chunk = ser.read(256)
                    if chunk:
                        fout.write(chunk)
                        fout.flush()
                        buf += chunk
                        while b"\n" in buf:
                            line, buf = buf.split(b"\n", 1)
                            if b"CoreMark 1.0 :" in line or b"CoreMark/MHz:" in line:
                                found_result = True
                        if found_result:
                            time.sleep(1.0)
                            remainder = ser.read(2048)
                            fout.write(remainder)
                            break
            if found_result:
                break
        except serial.SerialException:
            time.sleep(0.5)

if found_result:
    open(done_flag, "w").close()   # signal success to parent
PYEOF
    UART_PID=$!
else
    warn "pyserial not found — install with: pip install pyserial"
    warn "Falling back to stty+cat; output captured to ${UART_LOG}"
    stty -F "$UART_DEV" "$BAUD" cs8 -cstopb -parenb raw
    timeout "$TIMEOUT" cat "$UART_DEV" > "$UART_LOG" || true &
    UART_PID=$!
fi

sleep 0.5

# =============================================================================
# STEP 6 — Program the Arty A7  (listener is already running)
# =============================================================================
if [[ $DO_PROGRAM -eq 1 ]]; then
    sep
    info "Programming Arty A7 (UART listener already armed)..."

    if [[ "$PROGRAMMER" == "auto" ]]; then
        if   command -v openFPGALoader &>/dev/null; then PROGRAMMER=openFPGALoader
        elif command -v vivado         &>/dev/null; then PROGRAMMER=vivado
        else die "No programmer found. Install openFPGALoader or add Vivado to PATH."
        fi
    fi

    case "$PROGRAMMER" in
        openFPGALoader)
            info "Programming via openFPGALoader (board: arty_a7_100t)..."
            openFPGALoader --board arty_a7_100t "$BITFILE"
            ;;
        vivado)
            info "Programming via Vivado hw_server..."
            vivado -mode batch -source /dev/stdin <<VIVADO_TCL
open_hw_manager
connect_hw_server -allow_env_override
open_hw_target
set_property PROGRAM.FILE {${BITFILE}} [current_hw_device]
program_hw_devices [current_hw_device]
close_hw_target
VIVADO_TCL
            ;;
        *)
            die "Unknown programmer: $PROGRAMMER (choose openFPGALoader or vivado)"
            ;;
    esac
    ok "Board programmed — FPGA is now running CoreMark."
else
    warn "--no-program: skipping board programming."
    warn "Manually reset the board now to trigger UART output."
fi

# =============================================================================
# STEP 7 — Wait for the background listener, then print results
# =============================================================================
sep
info "Waiting for UART results (up to ${TIMEOUT}s)..."
wait "$UART_PID" || true

if [[ -s "$UART_LOG" ]]; then
    echo
    echo -e "${CYN}--- UART output from Takshaka @ ${BAUD}-8N1 ---${NC}"
    cat "$UART_LOG"
    echo -e "${CYN}--- End of UART capture ---${NC}"
    echo
fi

if [[ -f "$UART_DONE_FLAG" ]]; then
    rm -f "$UART_LOG" "$UART_DONE_FLAG"
    sep
    ok "Done."
    sep
else
    rm -f "$UART_LOG" "$UART_DONE_FLAG"
    sep
    warn "CoreMark result line not detected within ${TIMEOUT}s."
    warn "Tips:"
    warn "  1. Check UART device: ls /dev/ttyUSB*   (JTAG=ttyUSB0, UART=ttyUSB1)"
    warn "  2. Manually reset the board and re-run with --no-program"
    warn "  3. Increase timeout: --timeout 600"
    warn "  4. Monitor directly: python3 -m serial.tools.miniterm ${UART_DEV} ${BAUD}"
    sep
    exit 1
fi
