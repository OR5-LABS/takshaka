// ============================================================================
// takshaka_pmp.sv — RISC-V Physical Memory Protection (PMP) checker.
//
// Combinational access check for one memory reference (fetch / load / store).
// Implements the standard PMP matching modes per region — OFF / TOR / NA4 /
// NAPOT — with R/W/X permission bits and the L (lock) bit. This is the ISA
// feature behind M/U memory isolation in Ibex/OpenTitan, Hazard3, SHAKTI, etc.
//
//   * M-mode bypasses a region's permissions UNLESS that region is locked (L=1).
//   * The lowest-numbered matching region wins (RISC-V priority rule).
//   * No region matches: M-mode is allowed; U-mode is denied (when >=1 region
//     is implemented). With NPMP=0 the whole check is a pass-through.
//
// Config/address CSRs are passed in as flat vectors (one 8-bit cfg + one 32-bit
// addr per region) so the holder (the CSR file) owns the architectural state.
// ============================================================================


module takshaka_pmp #(
  parameter int NPMP = 8
)(
  input  wire [8*NPMP-1:0]  cfg,       // {pmpNcfg, ..., pmp0cfg}
  input  wire [32*NPMP-1:0] addrreg,   // {pmpaddrN, ..., pmpaddr0}
  input  wire [31:0]        addr,      // byte address of the access
  input  wire               priv_m,    // 1 = M-mode, 0 = U-mode
  input  wire               mmwp,      // mseccfg.MMWP: M-mode whitelist (no-match=deny)
  input  wire               do_r,      // load
  input  wire               do_w,      // store
  input  wire               do_x,      // instruction fetch
  output reg                fault      // 1 = access denied -> access-fault trap
);
  integer i;
  reg [NPMP-1:0] match, allow;
  reg            matched;
  reg            sel_allow;

  always_comb begin
    logic [7:0]  c;  logic [1:0] A;  logic L, X, W, R, perm;
    logic [31:0] pa, pa_prev, m, aw;
    aw = {2'b00, addr[31:2]};                 // address in 4-byte units (bits 33:2)
    match = '0; allow = '0;
    for (i = 0; i < NPMP; i = i + 1) begin
      c  = cfg[i*8 +: 8];
      A  = c[4:3]; L = c[7]; X = c[2]; W = c[1]; R = c[0];
      pa      = addrreg[i*32 +: 32];
      pa_prev = (i == 0) ? 32'd0 : addrreg[(i-1)*32 +: 32];
      m       = pa ^ (pa + 32'd1);            // NAPOT size mask (low run of 1s)
      unique case (A)
        2'd0: match[i] = 1'b0;                              // OFF
        2'd1: match[i] = (aw >= pa_prev) && (aw < pa);      // TOR
        2'd2: match[i] = (aw == pa);                        // NA4
        2'd3: match[i] = ((aw & ~m) == (pa & ~m));          // NAPOT
      endcase
      perm     = (do_x & X) | (do_r & R) | (do_w & W);
      allow[i] = (priv_m && !L) ? 1'b1 : perm;              // M bypasses unless locked
    end
    // lowest matching region wins (reverse scan so index 0 is last write)
    matched = 1'b0; sel_allow = 1'b0;
    for (i = NPMP-1; i >= 0; i = i - 1)
      if (match[i]) begin matched = 1'b1; sel_allow = allow[i]; end
    // no match: U always denied; M denied only under MMWP (whitelist policy)
    fault = matched ? ~sel_allow : (~priv_m | mmwp);
  end
endmodule
`default_nettype wire
