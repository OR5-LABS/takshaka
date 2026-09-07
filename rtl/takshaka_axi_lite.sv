// ============================================================================
// takshaka_axi_lite.sv — AXI4-Lite MASTER bridge for the Takshaka data port.
//
// E-class-grade cores ship a standard bus. This wrapper adapts Takshaka's simple
// request/response memory interface (the same addr/wdata/byte-strobe shape as the
// core's dmem port — dmem_addr/dmem_be/dmem_wdata/dmem_rdata plus dmem_re/dmem_we,
// here presented as a valid/ready handshake so a single-cycle core can be
// throttled) into a compliant AXI4-Lite MASTER: the five channels AW, W, B
// (writes) and AR, R (reads), each with VALID/READY handshakes and WSTRB byte
// strobes. One outstanding transaction at a time (AXI4-Lite permits this) —
// simple, correct, and directly synthesizable onto an AXI fabric.
//
// OPTIONAL: this is a standalone leaf cell. The existing non-AXI takshaka_soc and
// the `run.sh takshaka` compliance path never instantiate it, so they are
// byte-for-byte unchanged. A design that wants an AXI bus wraps the core's dmem
// port with this bridge: drive req_valid on (dmem_re | dmem_we), map dmem_be onto
// req_wstrb, and hold the core until req_ready is seen and rsp_valid returns.
//
// AXI4-Lite conventions honoured:
//   * 32-bit address + 32-bit data; WSTRB[3:0] byte strobes on writes.
//   * AW and W are issued together; B is accepted before the next request.
//   * AR/R for reads; RRESP/BRESP captured and surfaced (OKAY=00 expected,
//     SLVERR=10 propagated so the core/testbench can observe a bus error).
//   * All master-driven *VALID signals hold stable until the matching *READY,
//     and each channel's VALID drops the cycle after its handshake (per-channel
//     done flags for the write path where AW and W complete independently).
// ============================================================================
`include "takshaka_pkg.sv"

module takshaka_axi_lite
  import takshaka_pkg::*;
#(
  parameter int unsigned ADDR_W = 32,
  parameter int unsigned DATA_W = 32
)(
  input  logic                  clk,
  input  logic                  rst,        // active-high synchronous reset

  // ---- upstream: simple memory request/response (from the core side) --------
  input  logic                  req_valid,  // a load/store is requested
  output logic                  req_ready,  // bridge accepted the request
  input  logic                  req_write,  // 1 = store, 0 = load
  input  logic [ADDR_W-1:0]     req_addr,   // byte address
  input  logic [DATA_W-1:0]     req_wdata,  // store data (already lane-aligned)
  input  logic [DATA_W/8-1:0]   req_wstrb,  // byte strobes for the store (dmem_be)
  output logic                  rsp_valid,  // read/write completion (1 cycle)
  output logic [DATA_W-1:0]     rsp_rdata,  // load data (valid on a read rsp)
  output logic [1:0]            rsp_resp,   // AXI response (0=OKAY, 2=SLVERR)

  // ---- downstream: AXI4-Lite MASTER -----------------------------------------
  // Write address channel
  output logic [ADDR_W-1:0]     m_axi_awaddr,
  output logic [2:0]            m_axi_awprot,
  output logic                  m_axi_awvalid,
  input  logic                  m_axi_awready,
  // Write data channel
  output logic [DATA_W-1:0]     m_axi_wdata,
  output logic [DATA_W/8-1:0]   m_axi_wstrb,
  output logic                  m_axi_wvalid,
  input  logic                  m_axi_wready,
  // Write response channel
  input  logic [1:0]            m_axi_bresp,
  input  logic                  m_axi_bvalid,
  output logic                  m_axi_bready,
  // Read address channel
  output logic [ADDR_W-1:0]     m_axi_araddr,
  output logic [2:0]            m_axi_arprot,
  output logic                  m_axi_arvalid,
  input  logic                  m_axi_arready,
  // Read data channel
  input  logic [DATA_W-1:0]     m_axi_rdata,
  input  logic [1:0]            m_axi_rresp,
  input  logic                  m_axi_rvalid,
  output logic                  m_axi_rready
);
  // ---- FSM states -----------------------------------------------------------
  typedef enum logic [2:0] {
    S_IDLE,   // wait for a request
    S_WADDR,  // driving AW + W until both accepted
    S_WRESP,  // waiting for B
    S_RADDR,  // driving AR until accepted
    S_RDATA,  // waiting for R
    S_DONE    // pulse rsp_valid for one cycle
  } state_e;
  state_e state;

  // captured request + result
  logic [ADDR_W-1:0]   addr_q;
  logic [DATA_W-1:0]   wdata_q, rdata_q;
  logic [DATA_W/8-1:0] wstrb_q;
  logic [1:0]          resp_q;
  logic                aw_done, w_done;   // per-channel accepted flags for writes

  assign m_axi_awprot = 3'b000;
  assign m_axi_arprot = 3'b000;

  assign req_ready  = (state == S_IDLE);
  assign rsp_valid  = (state == S_DONE);
  assign rsp_rdata  = rdata_q;
  assign rsp_resp   = resp_q;

  // channel VALID/READY (combinational from state + per-channel done flags)
  assign m_axi_awaddr  = addr_q;
  assign m_axi_awvalid = (state == S_WADDR) && !aw_done;
  assign m_axi_wdata   = wdata_q;
  assign m_axi_wstrb   = wstrb_q;
  assign m_axi_wvalid  = (state == S_WADDR) && !w_done;
  assign m_axi_bready  = (state == S_WRESP);
  assign m_axi_araddr  = addr_q;
  assign m_axi_arvalid = (state == S_RADDR);
  assign m_axi_rready  = (state == S_RDATA);

  always_ff @(posedge clk) begin
    if (rst) begin
      state   <= S_IDLE;
      addr_q  <= '0; wdata_q <= '0; rdata_q <= '0; wstrb_q <= '0; resp_q <= 2'b00;
      aw_done <= 1'b0; w_done <= 1'b0;
    end else begin
      unique case (state)
        S_IDLE: begin
          aw_done <= 1'b0; w_done <= 1'b0;
          if (req_valid) begin
            addr_q  <= req_addr;
            wdata_q <= req_wdata;
            wstrb_q <= req_wstrb;
            if (req_write) state <= S_WADDR;
            else           state <= S_RADDR;
          end
        end
        // ---- WRITE: AW and W issued together, each retired on its handshake --
        S_WADDR: begin
          if (m_axi_awvalid && m_axi_awready) aw_done <= 1'b1;
          if (m_axi_wvalid  && m_axi_wready ) w_done  <= 1'b1;
          // advance once BOTH channels have been accepted
          if ((aw_done || (m_axi_awvalid && m_axi_awready)) &&
              (w_done  || (m_axi_wvalid  && m_axi_wready )))
            state <= S_WRESP;
        end
        S_WRESP: begin
          if (m_axi_bvalid && m_axi_bready) begin
            resp_q <= m_axi_bresp;
            state  <= S_DONE;
          end
        end
        // ---- READ: AR then R ------------------------------------------------
        S_RADDR: begin
          if (m_axi_arvalid && m_axi_arready) state <= S_RDATA;
        end
        S_RDATA: begin
          if (m_axi_rvalid && m_axi_rready) begin
            rdata_q <= m_axi_rdata;
            resp_q  <= m_axi_rresp;
            state   <= S_DONE;
          end
        end
        S_DONE: state <= S_IDLE;   // one-cycle rsp_valid pulse
        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
