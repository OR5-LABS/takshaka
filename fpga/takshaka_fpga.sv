// ============================================================================
// takshaka_fpga.sv — Synthesizable FPGA SoC for Takshaka (RV32IMC, 3-stage).
//
// Same board-independent SoC pattern as takshaka_fpga, minus the debug module
// (Takshaka has no DM yet). Unified distributed-RAM (async read, $readmemh init)
// + reused takshaka_uart + LEDs + minimal CLINT + tohost.
//
// Address map:
//   0x0000_0000.. : RAM (MEM_WORDS words)   0x1000_0000 : UART
//   0x0200_0000   : CLINT                    0x2000_0000 : tohost
//   0x2000_1000   : LED register
// ============================================================================
`include "takshaka_pkg.sv"


module takshaka_fpga
  import takshaka_pkg::*;
#(
  parameter int CLK_HZ     = 50_000_000,
  parameter int UART_BAUD  = 115_200,
  parameter int MEM_WORDS  = 4096,
  parameter     MEMFILE    = ""
)(
  input  wire        clk,
  input  wire        rst,
  output reg  [7:0]  leds,
  output wire        serial_tx,
  input  wire        serial_rx,
  output reg  [31:0] tohost,
  output reg         tohost_we
);
  localparam int AW = $clog2(MEM_WORDS);

  (* ram_style = "distributed" *) reg [31:0] mem [0:MEM_WORDS-1];
  initial if (MEMFILE != "") $readmemh(MEMFILE, mem);

  wire [31:0] imem_addr, imem_rdata;
  wire [31:0] dmem_addr, dmem_wdata;
  wire        dmem_re, dmem_we;
  wire [3:0]  dmem_be;
  logic [31:0] dmem_rdata;

  reg  [63:0] mtime, mtimecmp;
  reg         msip;
  wire        irq_timer = (mtime >= mtimecmp);
  wire        irq_soft  = msip;

  takshaka_core u_core (
    .clk(clk), .rst(rst),
    .imem_addr(imem_addr), .imem_rdata(imem_rdata),
    .dmem_addr(dmem_addr), .dmem_re(dmem_re), .dmem_we(dmem_we),
    .dmem_be(dmem_be), .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
    .irq_timer(irq_timer), .irq_soft(irq_soft), .irq_ext(1'b0),
    .retire_valid(), .retire_pc(), .retire_instr(),
    .retire_rd_we(), .retire_rd(), .retire_rd_val(),
    .dbg_haltreq(1'b0), .dbg_resumereq(1'b0), .dbg_halted(),
    .dbg_ar_valid(1'b0), .dbg_ar_write(1'b0), .dbg_ar_csr(1'b0),
    .dbg_ar_regno(12'd0), .dbg_ar_wdata(32'd0), .dbg_ar_rdata(), .dbg_ar_done()
  );

  assign imem_rdata = mem[imem_addr[AW+1:2]];

  wire in_ram    = (dmem_addr < MEM_WORDS*4);
  wire uart_sel  = (dmem_addr[31:16] == 16'h1000);
  wire clint_sel = (dmem_addr[31:16] == 16'h0200);
  wire led_sel   = (dmem_addr == 32'h2000_1000);
  wire tohost_sel= (dmem_addr == 32'h2000_0000);
  wire [AW-1:0] didx = dmem_addr[AW+1:2];

  wire [7:0] uart_rdata; wire uart_tx_irq, uart_rx_irq;
  takshaka_uart #(.CLK_HZ(CLK_HZ), .BAUD(UART_BAUD)) u_uart (
    .clk(clk), .rst(rst), .addr(dmem_addr[3:0]), .wdata(dmem_wdata[7:0]),
    .we(dmem_we && uart_sel), .re(dmem_re && uart_sel), .rdata(uart_rdata),
    .serial_tx(serial_tx), .serial_rx(serial_rx),
    .tx_irq(uart_tx_irq), .rx_irq(uart_rx_irq)
  );

  wire [31:0] clint_rdata =
        (dmem_addr[15:0]==16'h0000) ? {31'b0, msip}     :
        (dmem_addr[15:0]==16'h4000) ? mtimecmp[31:0]    :
        (dmem_addr[15:0]==16'h4004) ? mtimecmp[63:32]   :
        (dmem_addr[15:0]==16'hBFF8) ? mtime[31:0]       :
        (dmem_addr[15:0]==16'hBFFC) ? mtime[63:32]      : 32'h0;

  always_comb begin
    if      (uart_sel)  dmem_rdata = {24'h0, uart_rdata};
    else if (clint_sel) dmem_rdata = clint_rdata;
    else if (in_ram)    dmem_rdata = mem[didx];
    else                dmem_rdata = 32'h0;
  end

  always_ff @(posedge clk) begin
    tohost_we <= 1'b0;
    if (rst) begin
      mtime <= 64'd0; mtimecmp <= 64'hFFFF_FFFF_FFFF_FFFF; msip <= 1'b0; leds <= 8'h0;
    end else begin
      mtime <= mtime + 64'd1;
      if (dmem_we) begin
        if (in_ram) begin
          if (dmem_be[0]) mem[didx][7:0]   <= dmem_wdata[7:0];
          if (dmem_be[1]) mem[didx][15:8]  <= dmem_wdata[15:8];
          if (dmem_be[2]) mem[didx][23:16] <= dmem_wdata[23:16];
          if (dmem_be[3]) mem[didx][31:24] <= dmem_wdata[31:24];
        end else if (clint_sel) begin
          if (dmem_addr[15:0]==16'h0000) msip           <= dmem_wdata[0];
          if (dmem_addr[15:0]==16'h4000) mtimecmp[31:0] <= dmem_wdata;
          if (dmem_addr[15:0]==16'h4004) mtimecmp[63:32]<= dmem_wdata;
        end else if (led_sel)   leds <= dmem_wdata[7:0];
        else if (tohost_sel) begin tohost <= dmem_wdata; tohost_we <= 1'b1; end
      end
    end
  end
endmodule

`default_nettype wire
