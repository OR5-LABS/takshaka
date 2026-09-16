// ============================================================================
// takshaka_csr.sv — Machine-mode CSR file with trap/MRET support.
//
// Single read port (combinational) + single write port (CSR instructions),
// plus a trap interface used by the EX stage. Implements the minimal M-mode
// register set needed to take ECALL/EBREAK/illegal traps and return via MRET.
// ============================================================================
`include "takshaka_pkg.sv"

module takshaka_csr
  import takshaka_pkg::*;
#(
  // misa value advertised by this core. Default RV32IM; each core overrides to
  // reflect its true extensions (C, F, X-vector, ...). base=01 (32-bit) in
  // bits[31:30]; extension bit = (letter - 'A'): I=8, M=12, C=2, F=5, X=23.
  parameter logic [XLEN-1:0] MISA_VAL =
      (32'b01 << 30) | (1 << 8) /*I*/ | (1 << 12) /*M*/,
  // Security options (default OFF -> M-mode-only cores are byte-identical):
  parameter bit U_MODE      = 1'b0,   // add User privilege mode + misa[U]
  parameter int PMP_REGIONS = 0       // number of PMP regions (0 = no PMP)
)(
  input  logic              clk,
  input  logic              rst,

  // CSR instruction read/write (EX stage)
  input  logic [11:0]       csr_addr,
  output logic [XLEN-1:0]   csr_rdata,
  input  logic              csr_we,
  input  logic [XLEN-1:0]   csr_wdata,

  // ---- privilege + PMP (only meaningful when U_MODE / PMP_REGIONS set) ------
  output logic [1:0]        priv_o,      // current privilege (11=M, 00=U)
  output logic              fetch_m_o,   // instruction-fetch priv is M
  output logic              data_m_o,    // data-access priv is M (honours MPRV)
  output logic              mmwp_o,      // mseccfg.MMWP (ePMP M-mode whitelist)
  output logic [127:0]      pmpcfg_o,    // 16 pmpNcfg bytes
  output logic [511:0]      pmpaddr_o,   // 16 pmpaddrN words

  // Trap interface (EX stage)
  input  logic              trap_set,
  input  logic [3:0]        trap_cause,
  input  logic              trap_interrupt,   // 1 => mcause interrupt bit set
  input  logic [XLEN-1:0]   trap_epc,
  input  logic [XLEN-1:0]   trap_tval,
  input  logic              mret,
  input  logic              retire,     // an instruction committed this cycle

  // ---- Zihpm event strobes (assert in the cycle the event occurs) ----------
  // A programmable counter counts when its mhpmeventN selector matches an event
  // that is occurring this cycle. ev_cycle is implicitly always high (free-run).
  // Plain inputs (tie 0 if unused) — cores that share this leaf cell but don't
  // drive HPM events  leave them unconnected,
  // exactly like irq_* below. (No SV default-port value: sv2v emits those as regs,
  // which yosys rejects as "input port declared as register" and blocks synthesis.)
  input  logic              ev_branch,     // a branch retired
  input  logic              ev_brtaken,    // a taken branch retired
  input  logic              ev_load,       // a load retired
  input  logic              ev_store,      // a store retired

  // Interrupt pending lines (tie 0 if unused). Standard M-mode interrupts.
  input  logic              irq_timer,  // MTIP
  input  logic              irq_soft,   // MSIP
  input  logic              irq_ext,    // MEIP

  output logic [XLEN-1:0]   mtvec_o,
  output logic [XLEN-1:0]   mepc_o,
  output logic              irq_req,    // an enabled interrupt is pending+taken
  output logic [3:0]        irq_cause   // its cause code (11 ext / 7 timer / 3 soft)
);
  // Architectural registers
  logic [XLEN-1:0] mstatus;
  logic [XLEN-1:0] mtvec;
  logic [XLEN-1:0] mepc;
  logic [XLEN-1:0] mcause;
  logic [XLEN-1:0] mscratch;
  logic [XLEN-1:0] mtval;
  logic [XLEN-1:0] mie;
  logic [63:0]     mcycle;
  logic [63:0]     minstret;

  // ---- Zihpm programmable counters 3..6 + their event selectors ------------
  logic [63:0]     mhpmcounter [3:6];
  logic [5:0]      mhpmevent   [3:6];   // event code select (0=off)

  // ---- privilege + PMP state (active only when U_MODE / PMP_REGIONS set) ----
  logic [1:0]      priv;            // current privilege: 11=M, 00=U
  logic [127:0]    pmpcfg_r;        // 16 pmpNcfg bytes
  logic [511:0]    pmpaddr_r;       // 16 pmpaddrN words
  logic [2:0]      mseccfg;         // ePMP: {RLB[2], MMWP[1], MML[0]}
  integer          jb;              // pmpcfg byte loop index
  wire             rlb = mseccfg[2];

  // mstatus bit positions we model
  localparam int MIE_BIT  = 3;
  localparam int MPIE_BIT = 7;
  // MPP = bits [12:11]; MPRV = bit 17

  assign mtvec_o = mtvec;
  assign mepc_o  = mepc;

  // misa advertises U when User mode is configured (letter 'U' -> bit 20)
  wire [31:0] misa_eff = MISA_VAL | (U_MODE ? (32'd1 << 20) : 32'd0);

  assign priv_o    = priv;
  assign fetch_m_o = (priv == 2'b11);
  assign data_m_o  = (U_MODE && mstatus[17]) ? (mstatus[12:11]==2'b11) : (priv==2'b11);
  assign mmwp_o    = mseccfg[1];
  assign pmpcfg_o  = pmpcfg_r;
  assign pmpaddr_o = pmpaddr_r;

  wire is_pmpaddr = (csr_addr[11:4] == 8'h3B);                 // 0x3B0..0x3BF
  wire is_pmpcfg  = (csr_addr[11:2] == 10'h0E8);               // 0x3A0..0x3A3

  // misa is supplied by the MISA_VAL parameter (per-core true ISA advertisement).

  // hoisted const part-selects
  wire [31:0] mcycle_lo   = mcycle[31:0];
  wire [31:0] mcycle_hi   = mcycle[63:32];
  wire [31:0] minstret_lo = minstret[31:0];
  wire [31:0] minstret_hi = minstret[63:32];

  // ---- Zihpm: decode "does event code EV occur this cycle?" -----------------
  // Cycle counts every cycle; the others count when their retiring event fires.
  function automatic logic ev_occurs(input logic [5:0] ev);
    unique case (ev)
      HPM_EV_CYCLE  : ev_occurs = 1'b1;
      HPM_EV_INSTRET: ev_occurs = retire;
      HPM_EV_BRANCH : ev_occurs = ev_branch;
      HPM_EV_BRTAKEN: ev_occurs = ev_brtaken;
      HPM_EV_LOAD   : ev_occurs = ev_load;
      HPM_EV_STORE  : ev_occurs = ev_store;
      default       : ev_occurs = 1'b0;   // 0 or unknown = disabled
    endcase
  endfunction

  // ---- interrupts ----------------------------------------------------------
  // mip is read-only here, driven by the pending lines (MEIP/MTIP/MSIP).
  wire [31:0] mip = (irq_ext   << 11) | (irq_timer << 7) | (irq_soft << 3);
  wire        glob_ie = mstatus[MIE_BIT];
  // priority: external > timer > software
  assign irq_req   = glob_ie & ( (mip[11] & mie[11]) | (mip[7] & mie[7]) | (mip[3] & mie[3]) );
  assign irq_cause = (mip[11] & mie[11]) ? 4'd11 :
                     (mip[7]  & mie[7])  ? 4'd7  : 4'd3;

  // ---- read ----------------------------------------------------------------
  always_comb begin
    if (PMP_REGIONS > 0 && is_pmpaddr)
      csr_rdata = pmpaddr_r[csr_addr[3:0]*32 +: 32];
    else if (PMP_REGIONS > 0 && is_pmpcfg)
      csr_rdata = pmpcfg_r[csr_addr[1:0]*32 +: 32];
    else if (PMP_REGIONS > 0 && csr_addr == 12'h747)   // mseccfg
      csr_rdata = {29'b0, mseccfg};
    else unique case (csr_addr)
      CSR_MSTATUS  : csr_rdata = mstatus;
      CSR_MISA     : csr_rdata = misa_eff;
      CSR_MIE      : csr_rdata = mie;
      CSR_MTVEC    : csr_rdata = mtvec;
      CSR_MSCRATCH : csr_rdata = mscratch;
      CSR_MEPC     : csr_rdata = mepc;
      CSR_MCAUSE   : csr_rdata = mcause;
      CSR_MTVAL    : csr_rdata = mtval;
      CSR_MIP      : csr_rdata = mip;
      CSR_MCYCLE   : csr_rdata = mcycle_lo;
      CSR_MCYCLEH  : csr_rdata = mcycle_hi;
      CSR_MINSTRET : csr_rdata = minstret_lo;
      CSR_MINSTRETH: csr_rdata = minstret_hi;
      CSR_MHPMCOUNTER3 : csr_rdata = mhpmcounter[3][31:0];
      CSR_MHPMCOUNTER4 : csr_rdata = mhpmcounter[4][31:0];
      CSR_MHPMCOUNTER5 : csr_rdata = mhpmcounter[5][31:0];
      CSR_MHPMCOUNTER6 : csr_rdata = mhpmcounter[6][31:0];
      CSR_MHPMCOUNTER3H: csr_rdata = mhpmcounter[3][63:32];
      CSR_MHPMCOUNTER4H: csr_rdata = mhpmcounter[4][63:32];
      CSR_MHPMCOUNTER5H: csr_rdata = mhpmcounter[5][63:32];
      CSR_MHPMCOUNTER6H: csr_rdata = mhpmcounter[6][63:32];
      CSR_MHPMEVENT3 : csr_rdata = {26'd0, mhpmevent[3]};
      CSR_MHPMEVENT4 : csr_rdata = {26'd0, mhpmevent[4]};
      CSR_MHPMEVENT5 : csr_rdata = {26'd0, mhpmevent[5]};
      CSR_MHPMEVENT6 : csr_rdata = {26'd0, mhpmevent[6]};
      CSR_MVENDORID: csr_rdata = '0;
      CSR_MARCHID  : csr_rdata = 32'h41535452;   // "ASTR"
      CSR_MHARTID  : csr_rdata = '0;
      default      : csr_rdata = '0;
    endcase
  end

  // ---- write / trap / counters --------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      mstatus  <= '0;
      mtvec    <= '0;
      mepc     <= '0;
      mcause   <= '0;
      mscratch <= '0;
      mtval    <= '0;
      mie      <= '0;
      mcycle   <= '0;
      minstret <= '0;
      for (jb = 3; jb <= 6; jb = jb + 1) begin
        mhpmcounter[jb] <= '0;
        mhpmevent[jb]   <= 6'd0;               // all counters start disabled
      end
      priv      <= 2'b11;                      // start in M-mode
      pmpcfg_r  <= '0;
      pmpaddr_r <= '0;
      mseccfg   <= 3'b0;
    end else begin
      mcycle <= mcycle + 1'b1;
      if (retire) minstret <= minstret + 1'b1;

      // ---- Zihpm: each programmable counter increments when its selected event
      //      occurs this cycle. A same-cycle software write (below) overrides.
      for (jb = 3; jb <= 6; jb = jb + 1)
        if (ev_occurs(mhpmevent[jb]))
          mhpmcounter[jb] <= mhpmcounter[jb] + 1'b1;

      if (trap_set) begin
        // Enter trap: save context+priv, disable interrupts, vector to mtvec.
        mepc            <= trap_epc;
        mcause          <= {trap_interrupt, 27'd0, trap_cause};
        mtval           <= trap_tval;
        mstatus[MPIE_BIT] <= mstatus[MIE_BIT];
        mstatus[MIE_BIT]  <= 1'b0;
        mstatus[12:11]    <= U_MODE ? priv : 2'b11;   // MPP = interrupted priv
        if (U_MODE) priv  <= 2'b11;                    // traps run in M
      end else if (mret) begin
        mstatus[MIE_BIT]  <= mstatus[MPIE_BIT];
        mstatus[MPIE_BIT] <= 1'b1;
        if (U_MODE) begin
          priv           <= mstatus[12:11];            // restore interrupted priv
          mstatus[12:11] <= 2'b00;                      // MPP = U (least privilege)
          if (mstatus[12:11] != 2'b11) mstatus[17] <= 1'b0;  // MRET to <M clears MPRV
        end else mstatus[12:11] <= 2'b11;
      end else if (csr_we) begin
        if (PMP_REGIONS > 0 && is_pmpaddr) begin
          // a locked entry is immutable unless mseccfg.RLB (ePMP)
          if (!pmpcfg_r[csr_addr[3:0]*8 + 7] || rlb)
            pmpaddr_r[csr_addr[3:0]*32 +: 32] <= csr_wdata;
        end
        else if (PMP_REGIONS > 0 && is_pmpcfg) begin
          for (jb = 0; jb < 4; jb = jb + 1)
            if (!pmpcfg_r[(csr_addr[1:0]*4 + jb)*8 + 7] || rlb)   // per-entry lock
              pmpcfg_r[(csr_addr[1:0]*4 + jb)*8 +: 8] <= csr_wdata[jb*8 +: 8];
        end
        else if (PMP_REGIONS > 0 && csr_addr == 12'h747) begin    // mseccfg
          mseccfg[0] <= mseccfg[0] | csr_wdata[0];   // MML  sticky
          mseccfg[1] <= mseccfg[1] | csr_wdata[1];   // MMWP sticky
          mseccfg[2] <= csr_wdata[2];                // RLB
        end
        else unique case (csr_addr)
          CSR_MSTATUS  : mstatus  <= csr_wdata;
          CSR_MIE      : mie      <= csr_wdata;
          CSR_MTVEC    : mtvec    <= csr_wdata;
          CSR_MSCRATCH : mscratch <= csr_wdata;
          CSR_MEPC     : mepc     <= csr_wdata;
          CSR_MCAUSE   : mcause   <= csr_wdata;
          CSR_MTVAL    : mtval    <= csr_wdata;
          // Zihpm programmable counters + event selectors (writable)
          CSR_MHPMCOUNTER3 : mhpmcounter[3][31:0]  <= csr_wdata;
          CSR_MHPMCOUNTER4 : mhpmcounter[4][31:0]  <= csr_wdata;
          CSR_MHPMCOUNTER5 : mhpmcounter[5][31:0]  <= csr_wdata;
          CSR_MHPMCOUNTER6 : mhpmcounter[6][31:0]  <= csr_wdata;
          CSR_MHPMCOUNTER3H: mhpmcounter[3][63:32] <= csr_wdata;
          CSR_MHPMCOUNTER4H: mhpmcounter[4][63:32] <= csr_wdata;
          CSR_MHPMCOUNTER5H: mhpmcounter[5][63:32] <= csr_wdata;
          CSR_MHPMCOUNTER6H: mhpmcounter[6][63:32] <= csr_wdata;
          CSR_MHPMEVENT3   : mhpmevent[3] <= csr_wdata[5:0];
          CSR_MHPMEVENT4   : mhpmevent[4] <= csr_wdata[5:0];
          CSR_MHPMEVENT5   : mhpmevent[5] <= csr_wdata[5:0];
          CSR_MHPMEVENT6   : mhpmevent[6] <= csr_wdata[5:0];
          default      : /* read-only or unimplemented: ignore */ ;
        endcase
      end
    end
  end
endmodule
