// ============================================================================
// tb_takshaka_rvfi.sv — self-checking RVFI (RISC-V Formal Interface) testbench.
//
//   verilator --binary ... tb/tb_takshaka_rvfi.sv
//   sim/tb_takshaka_rvfi +IMEM=programs/build/smoke.hex
//
// Drives the smoke program and checks the core riscv-formal invariants on
// takshaka_core's RVFI port (proves the formal interface is wired correctly):
//   1. rvfi_order is contiguous (increments by exactly 1 per retire).
//   2. PC consistency: rvfi_pc_wdata[n] == rvfi_pc_rdata[n+1] (holds across
//      branches, jumps AND traps).
//   3. rvfi_insn is never x; x0 writes carry wdata==0.
// Reports RVFI: PASS / RVFI: FAIL.
// ============================================================================
`timescale 1ns/1ps

module tb_takshaka_rvfi;
  logic clk = 1'b0; always #5 clk = ~clk;
  logic rst;

  logic [31:0] tohost; logic tohost_we;
  logic        retire_valid; logic [31:0] retire_pc, retire_instr, retire_rd_val;
  logic        retire_rd_we; logic [4:0] retire_rd;

  takshaka_soc dut (
    .clk(clk), .rst(rst),
    .tck(1'b0), .tms(1'b0), .tdi(1'b0), .tdo(),
    .tohost(tohost), .tohost_we(tohost_we),
    .retire_valid(retire_valid), .retire_pc(retire_pc),
    .retire_instr(retire_instr), .retire_rd_we(retire_rd_we),
    .retire_rd(retire_rd), .retire_rd_val(retire_rd_val)
  );

  string  imem_file; integer i, errors = 0, checked = 0;

  initial begin
    if (!$value$plusargs("IMEM=%s", imem_file)) begin $display("FATAL no +IMEM"); $finish; end
    for (i = 0; i < 8192; i = i + 1) begin dut.imem[i] = 32'h0000_0013; dut.dram[i] = 32'h0; end
    $display("[RVFI] Loading IMEM from: %s", imem_file);
    $readmemh(imem_file, dut.imem);
    rst = 1'b1; repeat (4) @(posedge clk); rst = 1'b0;
  end

  logic [63:0] expect_order = 64'd0;
  logic [31:0] prev_pc_wdata;
  logic        have_prev = 1'b0;

  always @(posedge clk) begin
    if (!rst && dut.u_core.rvfi_valid) begin
      checked = checked + 1;
      if (dut.u_core.rvfi_order !== expect_order) begin
        $display("[RVFI] FAIL: order=%0d expected=%0d", dut.u_core.rvfi_order, expect_order);
        errors = errors + 1;
      end
      expect_order = dut.u_core.rvfi_order + 64'd1;
      if (have_prev && (dut.u_core.rvfi_pc_rdata !== prev_pc_wdata)) begin
        $display("[RVFI] FAIL: pc_rdata=%08x != prev pc_wdata=%08x (order %0d)",
                 dut.u_core.rvfi_pc_rdata, prev_pc_wdata, dut.u_core.rvfi_order);
        errors = errors + 1;
      end
      prev_pc_wdata = dut.u_core.rvfi_pc_wdata;
      have_prev     = 1'b1;
      if (^dut.u_core.rvfi_insn === 1'bx) begin
        $display("[RVFI] FAIL: rvfi_insn is X at order %0d", dut.u_core.rvfi_order);
        errors = errors + 1;
      end
      if (dut.u_core.rvfi_rd_addr == 5'd0 && dut.u_core.rvfi_rd_wdata != 32'd0) begin
        $display("[RVFI] FAIL: x0 write nonzero wdata at order %0d", dut.u_core.rvfi_order);
        errors = errors + 1;
      end
    end
  end

  integer cycle = 0;
  always @(posedge clk) begin
    if (!rst) cycle <= cycle + 1;
    if (tohost_we) begin
      $display("[RVFI] retires checked=%0d, errors=%0d", checked, errors);
      if (errors == 0 && tohost == 32'd1 && checked > 0) $display("RVFI: PASS");
      else $display("RVFI: FAIL");
      $finish;
    end
    if (cycle > 200000) begin $display("RVFI: FAIL (timeout)"); $finish; end
  end
endmodule
