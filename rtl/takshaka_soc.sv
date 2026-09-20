// ============================================================================
// takshaka_soc.sv — Minimal SoC wrapper for simulation/bring-up.
//
// Address map:
//   0x0000_0000 .. : IMEM  (program, word array, combinational read; data-port
//                    stores reach it only with IMEM_DATA_WRITE=1)
//   0x0200_xxxx    : CLINT (mtime/mtimecmp/msip)
//   0x1000_0000    : UART  (console: 0x0 tx/status, 0x4 rx, 0x8 baud)
//   0x2000_0000    : tohost (store here to end the test: 1=PASS, 2=FAIL)
//   0x8000_0000 .. : DRAM  (data, word array)
//
// IMEM is loaded from the +IMEM=<file> plusarg by the testbench via the
// public `imem` array. Functional model: combinational memory; the FPGA
// targets (see fpga/) wrap registered BRAM around the same core.
// ============================================================================
`include "takshaka_pkg.sv"

// Build-time selection of the SECURE configuration (M/U privilege, PMP and
// user-trap delegation): pass -DTAKSHAKA_SECURE, or override the SECURE parameter.
// -DTAKSHAKA_IMEM_WRITABLE (or IMEM_DATA_WRITE=1) lets data-port stores write IMEM
// (self-modifying / test code that keeps data in its code section); by default
// such stores are dropped.
`ifdef TAKSHAKA_IMEM_WRITABLE
  `define TAKSHAKA_SOC_IMEM_WRITE 1'b1
`else
  `define TAKSHAKA_SOC_IMEM_WRITE 1'b0
`endif
`ifdef TAKSHAKA_SECURE
  `define TAKSHAKA_SOC_SECURE 1'b1
`else
  `define TAKSHAKA_SOC_SECURE 1'b0
`endif

module takshaka_soc
  import takshaka_pkg::*;
#(
  parameter int unsigned IMEM_WORDS = 8192,
  parameter int unsigned DRAM_WORDS = 8192,
  parameter logic [XLEN-1:0] DRAM_BASE   = 32'h8000_0000,
  parameter logic [XLEN-1:0] TOHOST_ADDR = 32'h2000_0000,
  parameter logic [XLEN-1:0] UART_BASE   = 32'h1000_0000,
  parameter bit              SECURE      = `TAKSHAKA_SOC_SECURE,
  parameter bit              IMEM_DATA_WRITE = `TAKSHAKA_SOC_IMEM_WRITE
)(
  input  logic              clk,
  input  logic              rst,
  // JTAG debug pins (tie 0 if unused)
  input  logic              tck,
  input  logic              tms,
  input  logic              tdi,
  output logic              tdo,
  output logic [XLEN-1:0]   tohost,
  output logic              tohost_we,
  // retire trace, surfaced for the testbench
  output logic              retire_valid,
  output logic [XLEN-1:0]   retire_pc,
  output logic [XLEN-1:0]   retire_instr,
  output logic              retire_rd_we,
  output logic [4:0]        retire_rd,
  output logic [XLEN-1:0]   retire_rd_val
);
  // memories
  logic [XLEN-1:0] imem [0:IMEM_WORDS-1];
  logic [XLEN-1:0] dram [0:DRAM_WORDS-1];

  // core wires
  logic [XLEN-1:0] imem_addr, imem_rdata;
  logic [XLEN-1:0] dmem_addr, dmem_wdata, dmem_rdata;
  logic            dmem_re, dmem_we;
  logic [3:0]      dmem_be;

  // ---- CLINT (timer + software interrupt) ----------------------------------
  logic [63:0] mtime, mtimecmp; logic msip;
  wire irq_timer_w = (mtime >= mtimecmp);
  wire irq_soft_w  = msip;

  // ---- UART (console) ------------------------------------------------------
  wire in_uart = (dmem_addr[31:16] == UART_BASE[31:16]);
  wire [7:0] uart_rdata;
  takshaka_uart u_uart (
    .clk(clk), .rst(rst),
    .addr(dmem_addr[3:0]),
    .wdata(dmem_wdata[7:0]),
    .we(dmem_we && in_uart),
    .re(dmem_re && in_uart),
    .rdata(uart_rdata),
    .serial_tx(), .serial_rx(1'b1),
    .tx_irq(), .rx_irq()
  );

  // ---- debug module <-> core interface -------------------------------------
  wire        dbg_haltreq, dbg_resumereq, dbg_halted, ndmreset;
  wire        dbg_ar_valid, dbg_ar_write, dbg_ar_csr, dbg_ar_done;
  wire [11:0] dbg_ar_regno;
  wire [31:0] dbg_ar_wdata, dbg_ar_rdata;
  wire        dm_mem_valid, dm_mem_write;
  wire [31:0] dm_mem_addr, dm_mem_wdata;
  logic [31:0] dm_mem_rdata;
  logic        dm_mem_ready;
  wire core_rst = rst | ndmreset;

  takshaka_core #(.SECURE(SECURE)) u_core (
    .clk(clk), .rst(core_rst),
    .imem_addr(imem_addr), .imem_rdata(imem_rdata),
    .dmem_addr(dmem_addr), .dmem_re(dmem_re), .dmem_we(dmem_we),
    .dmem_be(dmem_be), .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
    .irq_timer(irq_timer_w), .irq_soft(irq_soft_w), .irq_ext(1'b0),
    .retire_valid(retire_valid), .retire_pc(retire_pc),
    .retire_instr(retire_instr), .retire_rd_we(retire_rd_we),
    .retire_rd(retire_rd), .retire_rd_val(retire_rd_val),
    .dbg_haltreq(dbg_haltreq), .dbg_resumereq(dbg_resumereq), .dbg_halted(dbg_halted),
    .dbg_ar_valid(dbg_ar_valid), .dbg_ar_write(dbg_ar_write), .dbg_ar_csr(dbg_ar_csr),
    .dbg_ar_regno(dbg_ar_regno), .dbg_ar_wdata(dbg_ar_wdata),
    .dbg_ar_rdata(dbg_ar_rdata), .dbg_ar_done(dbg_ar_done)
  );

  takshaka_debug #(.IDCODE(32'h5441_4B53)) u_dbg (   // "TAKS"
    .clk(clk), .rst(rst),
    .tck(tck), .tms(tms), .tdi(tdi), .tdo(tdo),
    .dbg_haltreq(dbg_haltreq), .dbg_resumereq(dbg_resumereq),
    .ndmreset(ndmreset), .dbg_halted(dbg_halted),
    .dbg_ar_valid(dbg_ar_valid), .dbg_ar_write(dbg_ar_write), .dbg_ar_csr(dbg_ar_csr),
    .dbg_ar_regno(dbg_ar_regno), .dbg_ar_wdata(dbg_ar_wdata),
    .dbg_ar_rdata(dbg_ar_rdata), .dbg_ar_done(dbg_ar_done),
    .dm_mem_valid(dm_mem_valid), .dm_mem_write(dm_mem_write),
    .dm_mem_addr(dm_mem_addr), .dm_mem_wdata(dm_mem_wdata),
    .dm_mem_rdata(dm_mem_rdata), .dm_mem_ready(dm_mem_ready)
  );

  // ---- instruction fetch (combinational) ----------------------------------
  wire [$clog2(IMEM_WORDS)-1:0] imem_idx = imem_addr[$clog2(IMEM_WORDS)+1:2];
  assign imem_rdata = imem[imem_idx];

  // ---- data read (combinational) ------------------------------------------
  wire in_dram = (dmem_addr >= DRAM_BASE) &&
                 (dmem_addr <  DRAM_BASE + DRAM_WORDS*4);
  wire [$clog2(DRAM_WORDS)-1:0] dram_idx =
        dmem_addr[$clog2(DRAM_WORDS)+1:2] - DRAM_BASE[$clog2(DRAM_WORDS)+1:2];

  wire in_imem = (dmem_addr < IMEM_WORDS*4);
  wire [$clog2(IMEM_WORDS)-1:0] imem_didx = dmem_addr[$clog2(IMEM_WORDS)+1:2];
  wire in_clint = (dmem_addr[31:16] == 16'h0200);
  wire [31:0] clint_rdata =
        (dmem_addr[15:0]==16'h0000) ? {31'b0, msip}    :
        (dmem_addr[15:0]==16'h4000) ? mtimecmp[31:0]   :
        (dmem_addr[15:0]==16'h4004) ? mtimecmp[63:32]  :
        (dmem_addr[15:0]==16'hBFF8) ? mtime[31:0]      :
        (dmem_addr[15:0]==16'hBFFC) ? mtime[63:32]     : 32'h0;
  assign dmem_rdata = in_dram  ? dram[dram_idx] :
                      in_clint ? clint_rdata :
                      in_uart  ? {24'h0, uart_rdata} :
                      in_imem  ? imem[imem_didx] : 32'h0;

  // ---- data write (synchronous) -------------------------------------------
  logic            tohost_we_r;
  logic [XLEN-1:0] tohost_r;
  assign tohost    = tohost_r;
  assign tohost_we = tohost_we_r;

  // byte-enable merge built in continuous assigns (avoids procedural selects)
  wire [XLEN-1:0] cur_word = dram[dram_idx];
  wire [XLEN-1:0] merged_word = {
    dmem_be[3] ? dmem_wdata[31:24] : cur_word[31:24],
    dmem_be[2] ? dmem_wdata[23:16] : cur_word[23:16],
    dmem_be[1] ? dmem_wdata[15:8]  : cur_word[15:8],
    dmem_be[0] ? dmem_wdata[7:0]   : cur_word[7:0]
  };
  wire [XLEN-1:0] cur_iword = imem[imem_didx];
  wire [XLEN-1:0] merged_imem = {
    dmem_be[3] ? dmem_wdata[31:24] : cur_iword[31:24],
    dmem_be[2] ? dmem_wdata[23:16] : cur_iword[23:16],
    dmem_be[1] ? dmem_wdata[15:8]  : cur_iword[15:8],
    dmem_be[0] ? dmem_wdata[7:0]   : cur_iword[7:0]
  };

  always_ff @(posedge clk) begin
    tohost_we_r <= 1'b0;
    if (rst) begin
      mtime <= 64'd0; mtimecmp <= 64'hFFFF_FFFF_FFFF_FFFF; msip <= 1'b0;
    end else begin
      mtime <= mtime + 64'd1;
    end
    if (dmem_we) begin
      if (in_dram) begin
        dram[dram_idx] <= merged_word;
      end else if (in_clint) begin
        if (dmem_addr[15:0]==16'h0000) msip            <= dmem_wdata[0];
        if (dmem_addr[15:0]==16'h4000) mtimecmp[31:0]  <= dmem_wdata;
        if (dmem_addr[15:0]==16'h4004) mtimecmp[63:32] <= dmem_wdata;
      end else if (dmem_addr == TOHOST_ADDR) begin
        tohost_r    <= dmem_wdata;
        tohost_we_r <= 1'b1;
      end else if (IMEM_DATA_WRITE && in_imem) begin
        imem[imem_didx] <= merged_imem;
      end
    end
  end

  // ---- Debug-Module System-Bus memory path (1-cycle latency) ---------------
  wire dm_in_dram = (dm_mem_addr >= DRAM_BASE) && (dm_mem_addr < DRAM_BASE + DRAM_WORDS*4);
  wire dm_in_imem = (dm_mem_addr < IMEM_WORDS*4);
  wire [$clog2(DRAM_WORDS)-1:0] dm_dram_idx =
        dm_mem_addr[$clog2(DRAM_WORDS)+1:2] - DRAM_BASE[$clog2(DRAM_WORDS)+1:2];
  wire [$clog2(IMEM_WORDS)-1:0] dm_imem_idx = dm_mem_addr[$clog2(IMEM_WORDS)+1:2];
  always_ff @(posedge clk) begin
    dm_mem_ready <= 1'b0;
    if (dm_mem_valid) begin
      dm_mem_ready <= 1'b1;
      if (dm_mem_write) begin
        if      (dm_in_dram) dram[dm_dram_idx] <= dm_mem_wdata;
        else if (dm_in_imem) imem[dm_imem_idx] <= dm_mem_wdata;
      end else begin
        dm_mem_rdata <= dm_in_dram ? dram[dm_dram_idx] :
                        dm_in_imem ? imem[dm_imem_idx] : 32'h0;
      end
    end
  end
endmodule
