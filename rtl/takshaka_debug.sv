// ============================================================================
// takshaka_debug.sv — RISC-V External Debug (Debug Spec 0.13.2) for Takshaka.
//
// Provides what PicoRV32 (only a partial/custom debug port) and a base SERV do
// not ship by default: a *standard* Debug Transport Module (JTAG DTM) + Debug
// Module (DM) that OpenOCD + GDB drive out of the box.
//
//   JTAG TAP (IDCODE / DTMCS / DMI / BYPASS)
//     └─ DMI  →  Debug Module registers
//                  dmcontrol / dmstatus / hartinfo
//                  abstractcs / command / data0   (Access Register: GPR + CSR)
//                  sbcs / sbaddress0 / sbdata0     (System Bus Access: memory)
//
// The whole transport runs in the core clock domain by oversampling TCK with a
// 2-FF synchroniser + rising-edge detect (TCK must be ≪ clk — true for any
// real JTAG adapter). This keeps the design single-clock: synthesizable and
// directly co-simulable with the core, no async DMI CDC FIFO needed.
//
// Hart access:
//   • halt/resume        via dmcontrol.haltreq / resumereq  → core boundary
//   • GPR & CSR          via Access-Register abstract command → core handshake
//   • memory             via System Bus Access master → SoC RAM arbiter
// ============================================================================


module takshaka_debug #(
  parameter logic [31:0] IDCODE = 32'h4B41_5641   // "KAVA", bit0=1 per JTAG
)(
  input  wire        clk,
  input  wire        rst,

  // ---- JTAG pins (driven by an external adapter; oversampled on clk) -------
  input  wire        tck,
  input  wire        tms,
  input  wire        tdi,
  output reg         tdo,

  // ---- hart control (to/from takshaka_core) ---------------------------------
  output wire        dbg_haltreq,
  output reg         dbg_resumereq,
  output wire        ndmreset,
  input  wire        dbg_halted,

  // abstract Access-Register handshake (serviced by the core while halted)
  output reg         dbg_ar_valid,
  output reg         dbg_ar_write,
  output reg         dbg_ar_csr,      // 1 = CSR, 0 = GPR
  output reg  [11:0] dbg_ar_regno,
  output reg  [31:0] dbg_ar_wdata,
  input  wire [31:0] dbg_ar_rdata,
  input  wire        dbg_ar_done,

  // ---- System Bus master (to SoC RAM arbiter) ------------------------------
  output reg         dm_mem_valid,
  output reg         dm_mem_write,
  output reg  [31:0] dm_mem_addr,
  output reg  [31:0] dm_mem_wdata,
  input  wire [31:0] dm_mem_rdata,
  input  wire        dm_mem_ready
);
  // ==========================================================================
  // 1. TCK oversampling
  // ==========================================================================
  reg [1:0] tck_s, tms_s, tdi_s;
  always @(posedge clk) begin
    tck_s <= {tck_s[0], tck};
    tms_s <= {tms_s[0], tms};
    tdi_s <= {tdi_s[0], tdi};
  end
  wire tck_rise = (tck_s == 2'b01);
  wire tms_q    = tms_s[1];
  wire tdi_q    = tdi_s[1];

  // ==========================================================================
  // 2. JTAG TAP state machine (IEEE 1149.1)
  // ==========================================================================
  localparam [3:0]
    TLR=0, RTI=1, SEL_DR=2, CAP_DR=3, SHF_DR=4, EX1_DR=5, PAU_DR=6, EX2_DR=7,
    UPD_DR=8, SEL_IR=9, CAP_IR=10, SHF_IR=11, EX1_IR=12, PAU_IR=13, EX2_IR=14,
    UPD_IR=15;
  reg [3:0] tap;

  always @(posedge clk) begin
    if (rst) tap <= TLR;
    else if (tck_rise) begin
      case (tap)
        TLR   : tap <= tms_q ? TLR    : RTI;
        RTI   : tap <= tms_q ? SEL_DR : RTI;
        SEL_DR: tap <= tms_q ? SEL_IR : CAP_DR;
        CAP_DR: tap <= tms_q ? EX1_DR : SHF_DR;
        SHF_DR: tap <= tms_q ? EX1_DR : SHF_DR;
        EX1_DR: tap <= tms_q ? UPD_DR : PAU_DR;
        PAU_DR: tap <= tms_q ? EX2_DR : PAU_DR;
        EX2_DR: tap <= tms_q ? UPD_DR : SHF_DR;
        UPD_DR: tap <= tms_q ? SEL_DR : RTI;
        SEL_IR: tap <= tms_q ? TLR    : CAP_IR;
        CAP_IR: tap <= tms_q ? EX1_IR : SHF_IR;
        SHF_IR: tap <= tms_q ? EX1_IR : SHF_IR;
        EX1_IR: tap <= tms_q ? UPD_IR : PAU_IR;
        PAU_IR: tap <= tms_q ? EX2_IR : PAU_IR;
        EX2_IR: tap <= tms_q ? UPD_IR : SHF_IR;
        UPD_IR: tap <= tms_q ? SEL_DR : RTI;
        default: tap <= TLR;
      endcase
    end
  end

  // ==========================================================================
  // 3. Instruction register
  // ==========================================================================
  localparam [4:0] IR_IDCODE=5'h01, IR_DTMCS=5'h10, IR_DMI=5'h11, IR_BYPASS=5'h1f;
  reg [4:0] ir, ir_shift;
  always @(posedge clk) begin
    if (rst) ir <= IR_IDCODE;
    else if (tck_rise) begin
      if (tap == TLR)        ir <= IR_IDCODE;
      else if (tap == CAP_IR) ir_shift <= 5'b00001;            // capture pattern
      else if (tap == SHF_IR) ir_shift <= {tdi_q, ir_shift[4:1]};
      else if (tap == UPD_IR) ir <= ir_shift;
    end
  end

  // ==========================================================================
  // 4. DMI / DTMCS / IDCODE / BYPASS data registers
  // ==========================================================================
  localparam int ABITS = 7;
  localparam int DMI_W = ABITS + 34;                 // addr + data[31:0] + op[1:0]

  // DTMCS (read mostly): version=1 (0.13), abits=7, idle=1
  wire [31:0] dtmcs_val = {14'd0, 3'd1 /*idle*/, 2'd0 /*dmistat*/,
                           6'd7 /*abits*/, 4'd1 /*version 0.13*/};

  reg [DMI_W-1:0] dr;          // generic shift register (sized to the widest, DMI)
  reg             bypass_bit;

  // captured DMI request fields
  wire [ABITS-1:0] dmi_addr = dr[DMI_W-1 : 34];
  wire [31:0]      dmi_data = dr[33 : 2];
  wire [1:0]       dmi_op   = dr[1:0];

  // value presented to the DMI read (filled at CAPTURE_DR from the DM regfile)
  reg  [31:0]      dmi_rdata;
  reg  [1:0]       dmi_rstat;

  // tdo (LSB-first shift out)
  always_comb begin
    case (ir)
      IR_IDCODE: tdo = dr[0];
      IR_DTMCS : tdo = dr[0];
      IR_DMI   : tdo = dr[0];
      default  : tdo = bypass_bit;     // BYPASS
    endcase
  end

  // ==========================================================================
  // 5. Debug Module register file
  // ==========================================================================
  reg        dmactive, ndmreset_r, haltreq_r;
  reg        resumeack;                 // sticky: hart acknowledged a resume
  reg        havereset;
  assign dbg_haltreq = haltreq_r & dmactive;
  assign ndmreset    = ndmreset_r;

  // abstractcs
  reg        abs_busy;
  reg [2:0]  cmderr;                    // 0 none,1 busy,2 not-supported,...

  // data0 (abstract data / scratch)
  reg [31:0] data0;

  // System Bus Access
  reg [31:0] sbaddress0, sbdata0;
  reg [2:0]  sbaccess;                  // log2 bytes; 2 = 32-bit
  reg        sbautoincrement, sbreadonaddr, sbreadondata;
  reg [2:0]  sberror;

  // dmstatus (assembled from hart state)
  wire [31:0] dmstatus_val = {
      9'd0,
      1'b0,                 // impebreak
      2'd0,
      resumeack, resumeack, // allresumeack / anyresumeack  [17:16]
      2'd0,                 // havereset (allhavereset/anyhavereset) [15:14] (simplified)
      1'b0,1'b0,
     ~dbg_halted, ~dbg_halted, // allrunning/anyrunning [11:10]
      dbg_halted, dbg_halted,  // allhalted/anyhalted   [9:8]
      1'b1,                 // authenticated [7]
      3'd0,
      4'd2                  // version = 2 (0.13)
  };

  wire [31:0] dmcontrol_val = {
      haltreq_r, 1'b0 /*resumereq reads 0*/, 1'b0, havereset, 4'd0,
      10'd0, 10'd0, 2'd0, ndmreset_r, dmactive };

  wire [31:0] abstractcs_val = {
      3'd0, 5'd0 /*progbufsize*/, 11'd0, abs_busy, 1'b0, cmderr, 4'd1 /*datacount*/ };

  wire [31:0] sbcs_val = {
      3'd1 /*sbversion*/, 6'd0, 1'b0 /*sbbusyerror*/, 1'b0 /*sbbusy*/,
      sbreadonaddr, sbaccess, sbautoincrement, sbreadondata, sberror,
      7'd32 /*sbasize*/, 1'b0,1'b0,1'b1 /*sbaccess32*/,1'b0,1'b0 };

  // read mux: DM register addressed by dmi_addr
  function [31:0] dm_read(input [ABITS-1:0] a);
    case (a)
      7'h04:   dm_read = data0;
      7'h10:   dm_read = dmcontrol_val;
      7'h11:   dm_read = dmstatus_val;
      7'h12:   dm_read = 32'h0;            // hartinfo
      7'h16:   dm_read = abstractcs_val;
      7'h17:   dm_read = 32'h0;            // command reads 0
      7'h38:   dm_read = sbcs_val;
      7'h39:   dm_read = sbaddress0;
      7'h3c:   dm_read = sbdata0;
      default: dm_read = 32'h0;
    endcase
  endfunction

  // ==========================================================================
  // 6. Abstract-command + System-Bus engine (clk domain)
  // ==========================================================================
  localparam [2:0] E_IDLE=0, E_AR=1, E_AR_WAIT=2, E_SB_RD=3, E_SB_WR=4, E_SB_WAIT=5;
  reg [2:0] eng;

  // a pending DMI write request from UPDATE_DR (1-cycle pulse)
  reg              dmi_we_pulse;
  reg [ABITS-1:0]  dmi_we_addr;
  reg [31:0]       dmi_we_data;

  task start_access_reg(input [31:0] cmd);
    begin
      // Access Register: regno[15:0], write[16], transfer[17], aarsize[22:20]
      if (cmd[31:24] != 8'd0) begin
        cmderr <= 3'd2;                  // only cmdtype 0 supported
      end else if (cmd[17] /*transfer*/) begin
        abs_busy     <= 1'b1;
        dbg_ar_regno <= cmd[11:0];
        dbg_ar_csr   <= (cmd[15:12] == 4'h0);   // 0x000-0xfff = CSR; 0x1000+ = GPR
        dbg_ar_write <= cmd[16];
        dbg_ar_wdata <= data0;
        dbg_ar_valid <= 1'b1;
        eng          <= E_AR_WAIT;
      end
    end
  endtask

  always @(posedge clk) begin
    if (rst) begin
      dmactive<=0; ndmreset_r<=0; haltreq_r<=0; resumeack<=0; havereset<=0;
      abs_busy<=0; cmderr<=0; data0<=0; dbg_resumereq<=0;
      dbg_ar_valid<=0; dbg_ar_write<=0; dbg_ar_csr<=0; dbg_ar_regno<=0; dbg_ar_wdata<=0;
      dm_mem_valid<=0; dm_mem_write<=0; dm_mem_addr<=0; dm_mem_wdata<=0;
      sbaddress0<=0; sbdata0<=0; sbaccess<=3'd2; sbautoincrement<=0;
      sbreadonaddr<=0; sbreadondata<=0; sberror<=0;
      eng<=E_IDLE;
    end else begin
      dbg_resumereq <= 1'b0;             // pulse
      dmi_we_pulse  <= 1'b0;

      // ---- TAP-driven DMI capture/shift/update ----------------------------
      if (tck_rise) begin
        case (tap)
          CAP_DR: begin
            case (ir)
              IR_IDCODE: dr <= {{(DMI_W-32){1'b0}}, IDCODE};
              IR_DTMCS : dr <= {{(DMI_W-32){1'b0}}, dtmcs_val};
              IR_DMI   : dr <= {{(ABITS){1'b0}}, dmi_rdata, dmi_rstat};
              default  : dr <= {DMI_W{1'b0}};
            endcase
          end
          SHF_DR: begin
            case (ir)
              IR_IDCODE, IR_DTMCS:
                       dr <= {{(DMI_W-32){1'b0}}, tdi_q, dr[31:1]};
              IR_DMI : dr <= {tdi_q, dr[DMI_W-1:1]};
              default: bypass_bit <= tdi_q;
            endcase
          end
          UPD_DR: begin
            if (ir == IR_DMI) begin
              if (dmi_op == 2'd1) begin                 // read
                dmi_rdata <= dm_read(dmi_addr);
                dmi_rstat <= 2'd0;
              end else if (dmi_op == 2'd2) begin        // write
                dmi_we_pulse <= 1'b1;
                dmi_we_addr  <= dmi_addr;
                dmi_we_data  <= dmi_data;
                dmi_rstat    <= 2'd0;
              end
            end
          end
          default: ;
        endcase
      end

      // ---- apply a latched DMI write to the DM register file ---------------
      if (dmi_we_pulse) begin
        case (dmi_we_addr)
          7'h04: data0 <= dmi_we_data;                       // data0
          7'h10: begin                                        // dmcontrol
                   dmactive   <= dmi_we_data[0];
                   if (!dmi_we_data[0]) begin haltreq_r<=0; ndmreset_r<=0; end
                   else begin
                     ndmreset_r <= dmi_we_data[1];
                     haltreq_r  <= dmi_we_data[31];
                     if (dmi_we_data[30] && dbg_halted) begin // resumereq
                       dbg_resumereq <= 1'b1; resumeack <= 1'b1;
                     end
                     if (dmi_we_data[28]) havereset <= 1'b0;  // ackhavereset
                   end
                 end
          7'h16: if (dmi_we_data[8]) cmderr <= 3'd0;          // abstractcs W1C cmderr
          7'h17: if (!abs_busy) start_access_reg(dmi_we_data);// command
          7'h38: begin                                        // sbcs
                   sbreadonaddr    <= dmi_we_data[20];
                   sbaccess        <= dmi_we_data[19:17];
                   sbautoincrement <= dmi_we_data[16];
                   sbreadondata    <= dmi_we_data[15];
                   if (dmi_we_data[14:12] != 3'd0) sberror <= 3'd0;  // W1C
                 end
          7'h39: begin                                        // sbaddress0
                   sbaddress0 <= dmi_we_data;
                   if (sbreadonaddr) begin
                     dm_mem_valid<=1; dm_mem_write<=0; dm_mem_addr<=dmi_we_data;
                     eng <= E_SB_RD;
                   end
                 end
          7'h3c: begin                                        // sbdata0
                   sbdata0 <= dmi_we_data;
                   dm_mem_valid<=1; dm_mem_write<=1;
                   dm_mem_addr<=sbaddress0; dm_mem_wdata<=dmi_we_data;
                   eng <= E_SB_WR;
                 end
          default: ;
        endcase
      end

      // ---- engine: service abstract reg + system-bus accesses --------------
      case (eng)
        E_AR_WAIT: begin
          dbg_ar_valid <= 1'b1;
          if (dbg_ar_done) begin
            dbg_ar_valid <= 1'b0;
            if (!dbg_ar_write) data0 <= dbg_ar_rdata;
            abs_busy <= 1'b0;
            eng <= E_IDLE;
          end
        end
        E_SB_RD: begin
          dm_mem_valid <= 1'b0;
          if (dm_mem_ready) begin
            sbdata0 <= dm_mem_rdata;
            if (sbautoincrement) sbaddress0 <= sbaddress0 + 32'd4;
            eng <= E_IDLE;
          end
        end
        E_SB_WR: begin
          dm_mem_valid <= 1'b0;
          if (dm_mem_ready) begin
            if (sbautoincrement) sbaddress0 <= sbaddress0 + 32'd4;
            eng <= E_IDLE;
          end
        end
        default: ;
      endcase
    end
  end
endmodule
`default_nettype wire
