// ============================================================================
// takshaka_rvc.sv — RV32C 16-bit → 32-bit instruction expander (combinational)
// ============================================================================



module takshaka_rvc (
  input  logic [15:0] instr16,
  output logic [31:0] instr32,
  output logic        is_compressed,
  output logic        decomp_illegal
);

  function automatic logic [4:0] rp (input logic [2:0] bits);
    rp = {2'b01, bits};
  endfunction

  logic [2:0] funct3;
  logic [1:0] quadrant;
  logic [4:0] rs2_full, rd_full, rs2_p, rd_p;

  assign funct3   = instr16[15:13];
  assign quadrant = instr16[1:0];
  assign rs2_full = instr16[6:2];
  assign rd_full  = instr16[11:7];
  assign rs2_p    = rp(instr16[4:2]);
  assign rd_p     = rp(instr16[9:7]);

  assign is_compressed = (instr16[1:0] != 2'b11);

  logic [9:0]  nzuimm;
  logic [6:0]  lw_off;
  logic [5:0]  nzimm6;
  logic [11:1] j_off;
  logic [9:0]  nzimm16;
  logic [5:0]  lui_nzimm;
  logic [8:1]  b_off;
  logic [5:0]  shamt6;
  logic [7:2]  lwsp_off;
  logic [7:2]  swsp_off;

  always_comb begin
    instr32        = {16'b0, instr16};
    decomp_illegal = 1'b0;
    nzuimm    = 10'h0; lw_off    = 7'h0;  nzimm6    = 6'h0;
    j_off     = 11'h0; nzimm16   = 10'h0; lui_nzimm = 6'h0;
    b_off     = 8'h0;  shamt6    = 6'h0;  lwsp_off  = 6'h0;
    swsp_off  = 6'h0;

    if (is_compressed) begin
      case (quadrant)

        2'b00: begin
          case (funct3)
            3'b000: begin
              nzuimm = {instr16[10:7], instr16[12:11], instr16[5], instr16[6], 2'b00};
              if (nzuimm == 10'h0) begin instr32 = 32'h0; decomp_illegal = 1'b1; end
              else instr32 = {2'b00, nzuimm, 5'd2, 3'b000, rs2_p, 7'b001_0011}; // rd' = inst[4:2]
            end
            3'b010: begin
              lw_off = {instr16[5], instr16[12:10], instr16[6], 2'b00};
              instr32 = {5'b0, lw_off, rd_p, 3'b010, rs2_p, 7'b000_0011};
            end
            3'b110: begin
              lw_off = {instr16[5], instr16[12:10], instr16[6], 2'b00};
              instr32 = {5'b0, lw_off[6], lw_off[5], rs2_p, rd_p,
                         3'b010, lw_off[4:0], 7'b010_0011};
            end
            // ---- Zcb: sub-word compressed loads/stores (funct3 = 100) --------
            // rd_p = rp(inst[9:7]) is rs1'; rs2_p = rp(inst[4:2]) is rd'/rs2'.
            3'b100: begin
              case (instr16[12:10])
                // C.LBU rd', uimm(rs1')  imm = {inst[5], inst[6]} (imm[1],imm[0])
                3'b000: instr32 = {5'b0, {5'b0, instr16[5], instr16[6]}, rd_p,
                                   3'b100, rs2_p, 7'b000_0011}; // lbu
                // C.LHU / C.LH  imm = {inst[5], 1'b0} (imm[1] only); inst[6] picks LH
                3'b001: begin
                  if (instr16[6])   // C.LH  -> lh rd', uimm(rs1')
                    instr32 = {5'b0, {5'b0, instr16[5], 1'b0}, rd_p,
                               3'b001, rs2_p, 7'b000_0011};
                  else              // C.LHU -> lhu rd', uimm(rs1')
                    instr32 = {5'b0, {5'b0, instr16[5], 1'b0}, rd_p,
                               3'b101, rs2_p, 7'b000_0011};
                end
                // C.SB rs2', uimm(rs1')  imm = {inst[5], inst[6]}
                3'b010: instr32 = {7'b0, rs2_p, rd_p, 3'b000,
                                   {3'b0, instr16[5], instr16[6]}, 7'b010_0011}; // sb
                // C.SH rs2', uimm(rs1')  imm = {inst[5], 1'b0}; inst[6] must be 0
                3'b011: begin
                  if (instr16[6]) begin instr32 = 32'h0; decomp_illegal = 1'b1; end
                  else instr32 = {7'b0, rs2_p, rd_p, 3'b001,
                                  {3'b0, instr16[5], 1'b0}, 7'b010_0011}; // sh
                end
                default: begin instr32 = 32'h0; decomp_illegal = 1'b1; end
              endcase
            end
            default: begin instr32 = 32'h0; decomp_illegal = 1'b1; end
          endcase
        end

        2'b01: begin
          case (funct3)
            3'b000: begin
              nzimm6  = {instr16[12], instr16[6:2]};
              instr32 = {{6{nzimm6[5]}}, nzimm6, rd_full, 3'b000, rd_full, 7'b001_0011};
            end
            3'b001: begin
              j_off = {instr16[12], instr16[8], instr16[10:9], instr16[6],
                       instr16[7],  instr16[2], instr16[11],   instr16[5:3]};
              instr32 = {j_off[11], j_off[10:1], j_off[11], {8{j_off[11]}},
                         5'd1, 7'b110_1111};
            end
            3'b010: begin
              nzimm6  = {instr16[12], instr16[6:2]};
              instr32 = {{6{nzimm6[5]}}, nzimm6, 5'd0, 3'b000, rd_full, 7'b001_0011};
            end
            3'b011: begin
              if (rd_full == 5'd2) begin
                nzimm16 = {instr16[12], instr16[4:3], instr16[5],
                           instr16[2],  instr16[6],   4'b0000};
                if (nzimm16 == 10'h0) begin instr32 = 32'h0; decomp_illegal = 1'b1; end
                else instr32 = {{2{nzimm16[9]}}, nzimm16, 5'd2, 3'b000, 5'd2, 7'b001_0011};
              end else if (rd_full == 5'd0) begin
                instr32 = 32'h0; decomp_illegal = 1'b1;
              end else begin
                lui_nzimm = {instr16[12], instr16[6:2]};
                if (lui_nzimm == 6'h0) begin instr32 = 32'h0; decomp_illegal = 1'b1; end
                else instr32 = {{14{lui_nzimm[5]}}, lui_nzimm, rd_full, 7'b011_0111};
              end
            end
            3'b100: begin
              shamt6 = {instr16[12], instr16[6:2]};
              case (instr16[11:10])
                2'b00: begin
                  if (shamt6[5]) begin instr32 = 32'h0; decomp_illegal = 1'b1; end
                  else instr32 = {7'b000_0000, shamt6[4:0], rd_p, 3'b101, rd_p, 7'b001_0011};
                end
                2'b01: begin
                  if (shamt6[5]) begin instr32 = 32'h0; decomp_illegal = 1'b1; end
                  else instr32 = {7'b010_0000, shamt6[4:0], rd_p, 3'b101, rd_p, 7'b001_0011};
                end
                2'b10: instr32 = {{6{shamt6[5]}}, shamt6, rd_p, 3'b111, rd_p, 7'b001_0011};
                2'b11: begin
                  case ({instr16[12], instr16[6:5]})
                    3'b000: instr32 = {7'b010_0000, rs2_p, rd_p, 3'b000, rd_p, 7'b011_0011};
                    3'b001: instr32 = {7'b000_0000, rs2_p, rd_p, 3'b100, rd_p, 7'b011_0011};
                    3'b010: instr32 = {7'b000_0000, rs2_p, rd_p, 3'b110, rd_p, 7'b011_0011};
                    3'b011: instr32 = {7'b000_0000, rs2_p, rd_p, 3'b111, rd_p, 7'b011_0011};
                    // ---- Zcb Q1: C.MUL and unary ops (inst[12]=1) -----------
                    3'b110: // C.MUL rd', rd', rs2'  -> mul
                      instr32 = {7'b000_0001, rs2_p, rd_p, 3'b000, rd_p, 7'b011_0011};
                    3'b111: begin  // unary ops, selected by inst[4:2]
                      case (instr16[4:2])
                        // C.ZEXT.B -> andi rd', rd', 0xff
                        3'b000: instr32 = {12'h0FF, rd_p, 3'b111, rd_p, 7'b001_0011};
                        // C.SEXT.B -> sext.b (Zbb): OP-IMM funct7=0110000, funct3=001, rs2=00100
                        3'b001: instr32 = {7'b011_0000, 5'b00100, rd_p, 3'b001, rd_p, 7'b001_0011};
                        // C.ZEXT.H -> zext.h (Zbb): OP funct7=0000100, funct3=100, rs2=00000
                        3'b010: instr32 = {7'b000_0100, 5'b00000, rd_p, 3'b100, rd_p, 7'b011_0011};
                        // C.SEXT.H -> sext.h (Zbb): OP-IMM funct7=0110000, funct3=001, rs2=00101
                        3'b011: instr32 = {7'b011_0000, 5'b00101, rd_p, 3'b001, rd_p, 7'b001_0011};
                        // C.NOT -> xori rd', rd', -1
                        3'b101: instr32 = {12'hFFF, rd_p, 3'b100, rd_p, 7'b001_0011};
                        // 3'b100 = C.ZEXT.W (RV64 only) — illegal on RV32
                        default: begin instr32 = 32'h0; decomp_illegal = 1'b1; end
                      endcase
                    end
                    default: begin instr32 = 32'h0; decomp_illegal = 1'b1; end
                  endcase
                end
              endcase
            end
            3'b101: begin
              j_off = {instr16[12], instr16[8], instr16[10:9], instr16[6],
                       instr16[7],  instr16[2], instr16[11],   instr16[5:3]};
              instr32 = {j_off[11], j_off[10:1], j_off[11], {8{j_off[11]}},
                         5'd0, 7'b110_1111};
            end
            3'b110: begin  // C.BEQZ -> beq rd', x0, off
              b_off = {instr16[12], instr16[6:5], instr16[2],
                       instr16[11:10], instr16[4:3]};
              // B-type imm: {imm12, imm[10:5], rs2, rs1, f3, imm[4:1], imm11}.
              // CB offset is 9-bit signed (off[8:1]); sign-extend off[8] into
              // imm[12], imm[11], imm[10:8].
              instr32 = {{4{b_off[8]}}, b_off[7:5], 5'd0, rd_p,
                         3'b000, b_off[4:1], b_off[8], 7'b110_0011};
            end
            3'b111: begin  // C.BNEZ -> bne rd', x0, off
              b_off = {instr16[12], instr16[6:5], instr16[2],
                       instr16[11:10], instr16[4:3]};
              instr32 = {{4{b_off[8]}}, b_off[7:5], 5'd0, rd_p,
                         3'b001, b_off[4:1], b_off[8], 7'b110_0011};
            end
            default: begin instr32 = 32'h0; decomp_illegal = 1'b1; end
          endcase
        end

        2'b10: begin
          case (funct3)
            3'b000: begin
              shamt6 = {instr16[12], instr16[6:2]};
              if (shamt6[5] || (shamt6 == 6'h0)) begin
                instr32 = 32'h0; decomp_illegal = 1'b1;
              end else instr32 = {7'b000_0000, shamt6[4:0], rd_full, 3'b001, rd_full, 7'b001_0011};
            end
            3'b010: begin
              lwsp_off = {instr16[3:2], instr16[12], instr16[6:4]};
              if (rd_full == 5'd0) begin instr32 = 32'h0; decomp_illegal = 1'b1; end
              else instr32 = {4'b0, lwsp_off, 2'b00, 5'd2, 3'b010, rd_full, 7'b000_0011};
            end
            3'b100: begin
              if (!instr16[12]) begin
                if (rs2_full == 5'd0) begin
                  if (rd_full == 5'd0) begin instr32 = 32'h0; decomp_illegal = 1'b1; end
                  else instr32 = {12'h0, rd_full, 3'b000, 5'd0, 7'b110_0111};
                end else begin
                  instr32 = {7'b000_0000, rs2_full, 5'd0, 3'b000, rd_full, 7'b011_0011};
                end
              end else begin
                if (rs2_full == 5'd0) begin
                  if (rd_full == 5'd0) instr32 = 32'h0010_0073; // C.EBREAK
                  else                 instr32 = {12'h0, rd_full, 3'b000, 5'd1, 7'b110_0111};
                end else begin
                  instr32 = {7'b000_0000, rs2_full, rd_full, 3'b000, rd_full, 7'b011_0011};
                end
              end
            end
            3'b110: begin
              swsp_off = {instr16[8:7], instr16[12:9]};
              instr32 = {4'b0, swsp_off[7:6], swsp_off[5], rs2_full,
                         5'd2, 3'b010, swsp_off[4:2], 2'b00, 7'b010_0011};
            end
            default: begin instr32 = 32'h0; decomp_illegal = 1'b1; end
          endcase
        end

        default: begin
          instr32 = {16'b0, instr16}; decomp_illegal = 1'b0;
        end
      endcase
    end
  end

endmodule

`default_nettype wire
