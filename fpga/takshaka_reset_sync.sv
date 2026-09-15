// ============================================================================
// takshaka_reset_sync.sv
//
// Async-assert / sync-deassert reset synchronizer.
//
// Reset asserts asynchronously (a glitching async reset can be captured
// immediately by every flop with no clock), but deasserts synchronously on
// the rising edge of clk through a chain of DEPTH flip-flops so the rest of
// the design comes out of reset cleanly without metastability hazards.
//
// Parameters:
//   DEPTH       - length of the synchronizer chain (default 3, min 2).
//   ACTIVE_HIGH - 1 = active-high reset, 0 = active-low reset.
//
// Notes for FPGA:
//   In Xilinx flow, mark the chain with ASYNC_REG = "TRUE" so the placer
//   keeps the flops together and they get into IOB/SLICEM fast routes.
// ============================================================================



module takshaka_reset_sync #(
    parameter int  DEPTH       = 3,
    parameter bit  ACTIVE_HIGH = 1'b1
) (
    input  logic clk,
    input  logic async_rst_in,
    output logic sync_rst_out
);

  // Internal async-reset value: when async_rst_in indicates "reset asserted",
  // every flop is held at the "asserted" value (1 for active-high, 0 for
  // active-low).  When async_rst_in is deasserted, ones (active-high) or
  // zeros (active-low) are shifted through the chain.
  localparam bit ASSERTED = ACTIVE_HIGH ? 1'b1 : 1'b0;
  localparam bit RELEASED = ACTIVE_HIGH ? 1'b0 : 1'b1;

  (* ASYNC_REG = "TRUE" *)
  logic [DEPTH-1:0] sync_chain;

  // Async reset of the chain.  In active-high mode, an asserted async_rst_in
  // forces the chain to all-1s; in active-low mode, an asserted (==0)
  // async_rst_in forces the chain to all-0s.
  generate
    if (ACTIVE_HIGH) begin : g_active_high
      always_ff @(posedge clk or posedge async_rst_in) begin
        if (async_rst_in) begin
          sync_chain <= {DEPTH{ASSERTED}};
        end else begin
          sync_chain <= {sync_chain[DEPTH-2:0], RELEASED};
        end
      end
    end else begin : g_active_low
      always_ff @(posedge clk or negedge async_rst_in) begin
        if (!async_rst_in) begin
          sync_chain <= {DEPTH{ASSERTED}};
        end else begin
          sync_chain <= {sync_chain[DEPTH-2:0], RELEASED};
        end
      end
    end
  endgenerate

  assign sync_rst_out = sync_chain[DEPTH-1];

endmodule

`default_nettype wire
