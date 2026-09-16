// ============================================================================
// takshaka_muldiv.sv — RV32M multiply/divide unit (multi-cycle).
//
//   * MUL family : 1-cycle latched 64-bit product (picks hi/lo, signedness).
//   * DIV family : iterative shift-subtract over magnitudes (32 steps) plus a
//                  sign-fixup cycle. Implements RISC-V div-by-zero/overflow.
//
// Handshake: pulse `start` for one cycle with op/a/b valid. `busy` stays high
// while computing; `done` pulses for one cycle when `result` is valid.
// ============================================================================
`include "takshaka_pkg.sv"

module takshaka_muldiv
  import takshaka_pkg::*;
(
  input  logic              clk,
  input  logic              rst,
  input  logic              start,
  input  md_op_e            op,
  input  logic [XLEN-1:0]   a,
  input  logic [XLEN-1:0]   b,
  output logic              busy,
  output logic              done,
  output logic [XLEN-1:0]   result
);
  typedef enum logic [1:0] { S_IDLE, S_MUL, S_DIV, S_FIN } state_e;
  state_e state;

  md_op_e          op_q;
  logic [XLEN-1:0] a_q, b_q;

  // ---- multiply: combinational 64-bit product on latched operands ----------
  // Operands are explicitly extended to 64 bits BEFORE the multiply so the full
  // product is formed (a 32x32 product needs 64-bit operands in the multiply;
  // relying on context width mis-computes the high word — caught by riscv-tests
  // mulh/mulhsu). se_* = sign-extended, ze_* = zero-extended.
  wire [63:0] se_a = {{32{a_q[31]}}, a_q};
  wire [63:0] se_b = {{32{b_q[31]}}, b_q};
  wire [63:0] ze_a = {32'b0, a_q};
  wire [63:0] ze_b = {32'b0, b_q};
  logic [63:0] prod;
  always_comb begin
    unique case (op_q)
      MD_MUL, MD_MULH : prod = se_a * se_b;   // signed x signed
      MD_MULHSU       : prod = se_a * ze_b;   // signed x unsigned
      default         : prod = ze_a * ze_b;   // MULHU / MUL (unsigned)
    endcase
  end
  // hoisted const part-selects
  wire [31:0] prod_lo = prod[31:0];
  wire [31:0] prod_hi = prod[63:32];

  // ---- division working state ----------------------------------------------
  logic [4:0]      bit_idx;       // current dividend bit (31 .. 0)
  logic [XLEN-1:0] dividend_mag;  // |dividend|
  logic [XLEN-1:0] divisor_mag;   // |divisor|
  logic [XLEN-1:0] quotient_q;
  logic [XLEN:0]   rem_q;         // 33-bit running remainder
  logic            neg_quot, neg_rem;
  logic            div_by_zero, div_overflow;
  logic [XLEN-1:0] dividend_raw;

  wire  [31:0]     rem_lo = rem_q[XLEN-1:0];
  wire  [XLEN:0]   rem_shifted = {rem_lo, dividend_mag[bit_idx]};

  assign busy = (state != S_IDLE);

  always_ff @(posedge clk) begin
    if (rst) begin
      state  <= S_IDLE;
      done   <= 1'b0;
      result <= '0;
    end else begin
      done <= 1'b0;
      case (state)
        // ---------------------------------------------------------------
        S_IDLE: if (start) begin
          op_q <= op;
          a_q  <= a;
          b_q  <= b;
          if ((op == MD_MUL) || (op == MD_MULH) ||
              (op == MD_MULHSU) || (op == MD_MULHU)) begin
            state <= S_MUL;
          end else begin
            div_by_zero  <= (b == 32'd0);
            div_overflow <= ((op == MD_DIV || op == MD_REM) &&
                             (a == 32'h8000_0000) && (b == 32'hFFFF_FFFF));
            dividend_raw <= a;
            dividend_mag <= ((op==MD_DIV || op==MD_REM) && a[31]) ? (~a + 1'b1) : a;
            divisor_mag  <= ((op==MD_DIV || op==MD_REM) && b[31]) ? (~b + 1'b1) : b;
            quotient_q   <= '0;
            rem_q        <= '0;
            neg_quot     <= (op==MD_DIV) && (a[31] ^ b[31]);
            neg_rem      <= (op==MD_REM) && a[31];
            bit_idx      <= 5'd31;
            state        <= S_DIV;
          end
        end
        // ---------------------------------------------------------------
        S_MUL: begin
          result <= (op_q == MD_MUL) ? prod_lo : prod_hi;
          done   <= 1'b1;
          state  <= S_IDLE;
        end
        // ---------------------------------------------------------------
        S_DIV: begin
          if (div_by_zero) begin
            result <= (op_q == MD_DIV)  ? 32'hFFFF_FFFF :
                      (op_q == MD_DIVU) ? 32'hFFFF_FFFF : dividend_raw;
            done   <= 1'b1;
            state  <= S_IDLE;
          end else if (div_overflow) begin
            result <= (op_q == MD_DIV) ? 32'h8000_0000 : 32'd0;
            done   <= 1'b1;
            state  <= S_IDLE;
          end else begin
            if (rem_shifted >= {1'b0, divisor_mag}) begin
              rem_q      <= rem_shifted - {1'b0, divisor_mag};
              quotient_q <= (quotient_q << 1) | 32'd1;
            end else begin
              rem_q      <= rem_shifted;
              quotient_q <= (quotient_q << 1);
            end
            if (bit_idx == 5'd0) state   <= S_FIN;
            else                 bit_idx <= bit_idx - 1'b1;
          end
        end
        // ---------------------------------------------------------------
        S_FIN: begin
          unique case (op_q)
            MD_DIV  : result <= neg_quot ? (~quotient_q + 1'b1) : quotient_q;
            MD_DIVU : result <= quotient_q;
            MD_REM  : result <= neg_rem  ? (~rem_lo + 1'b1) : rem_lo;
            default : result <= rem_lo;        // REMU
          endcase
          done  <= 1'b1;
          state <= S_IDLE;
        end
        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
