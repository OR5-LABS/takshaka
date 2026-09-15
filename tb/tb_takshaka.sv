// ============================================================================
// tb_takshaka.sv — Self-checking testbench for takshaka_soc.
//
//   vvp sim/tb_takshaka +IMEM=programs/build/smoke.hex
//   vvp sim/tb_takshaka +IMEM=... +TRACE=1   (emit retire trace for co-sim)
//
// Exit protocol: a store to tohost (0x2000_0000) ends the run.
//   tohost == 1  -> PASS
//   tohost != 1  -> FAIL
// ============================================================================
`timescale 1ns/1ps

module tb_takshaka;
  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst;

  logic [31:0] tohost;
  logic        tohost_we;
  logic        retire_valid;
  logic [31:0] retire_pc, retire_instr, retire_rd_val;
  logic        retire_rd_we;
  logic [4:0]  retire_rd;

  takshaka_soc dut (
    .clk(clk), .rst(rst),
    .tck(1'b0), .tms(1'b0), .tdi(1'b0), .tdo(),
    .tohost(tohost), .tohost_we(tohost_we),
    .retire_valid(retire_valid), .retire_pc(retire_pc),
    .retire_instr(retire_instr), .retire_rd_we(retire_rd_we),
    .retire_rd(retire_rd), .retire_rd_val(retire_rd_val)
  );

  string imem_file;
  integer trace_en;
  integer i;

  initial begin
    if (!$value$plusargs("IMEM=%s", imem_file)) begin
      $display("FATAL: no +IMEM=<file> given");
      $finish;
    end
    trace_en = 0;
    if ($value$plusargs("TRACE=%d", trace_en)) ;

    // clear memories
    for (i = 0; i < 8192; i = i + 1) begin
      dut.imem[i] = 32'h0000_0013;   // NOP fill
      dut.dram[i] = 32'h0;
    end

    $display("[TB] Loading IMEM from: %s", imem_file);
    $readmemh(imem_file, dut.imem);

    if ($test$plusargs("VCD")) begin
      $dumpfile("tb_takshaka.vcd");
      $dumpvars(0, tb_takshaka);
    end

    rst = 1'b1;
    repeat (4) @(posedge clk);
    rst = 1'b0;
    $display("[TB] Reset released");
  end

  // retire trace for co-simulation
  always @(posedge clk) begin
    if (!rst && trace_en && retire_valid) begin
      $display("RETIRE pc=%08x instr=%08x rdwe=%0d rd=%0d rdval=%08x",
               retire_pc, retire_instr, retire_rd_we, retire_rd, retire_rd_val);
    end
  end

  // exit on tohost
  integer cycle = 0;
  always @(posedge clk) begin
    if (!rst) cycle <= cycle + 1;
    if (tohost_we) begin
      $display("[TB] tohost write: 0x%08x at cycle %0d", tohost, cycle);
      if (tohost == 32'd1) $display("[TB] PASS");
      else                 $display("[TB] FAIL (code %0d)", tohost);
      $finish;
    end
    if (cycle > 50000000) begin   // raised for CoreMark (one iteration ~0.3M cyc)
      $display("[TB] TIMEOUT — no tohost write");
      $finish;
    end
  end
endmodule
