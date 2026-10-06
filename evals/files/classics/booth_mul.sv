// Reference radix-4 Booth multiplier (only used to validate booth_mul_tb.sv).
// The start edge captures the operands; Width/2 iteration edges follow, each
// adding one Booth digit times the multiplicand; the last one drops busy_o and
// raises done_o for one cycle.
module booth_mul #(
    parameter int Width = 16
) (
    input  logic               clk_i,
    input  logic               rst_ni,
    input  logic               start_i,
    input  logic [Width-1:0]   a_i,
    input  logic [Width-1:0]   b_i,
    output logic               busy_o,
    output logic               done_o,
    output logic [2*Width-1:0] product_o
);
    if (Width < 4 || Width % 2 != 0) begin : gen_bad_width
        $error("booth_mul: Width must be even and at least 4");
    end

    localparam int CntW = $clog2(Width / 2 + 1);

    logic [CntW-1:0]    cnt_q;
    logic [2*Width-1:0] mcand_q;  // sign-extended multiplicand, shifted left 2 per step
    logic [Width:0]     mplier_q; // {multiplier, implicit 0}, shifted right 2 per step
    logic [2*Width-1:0] acc_q;
    logic [2*Width-1:0] pp;

    // Booth digit from {b[2i+1], b[2i], b[2i-1]}.
    always_comb begin
        unique case (mplier_q[2:0])
            3'b001, 3'b010: pp = mcand_q;
            3'b011:         pp = mcand_q << 1;
            3'b100:         pp = -(mcand_q << 1);
            3'b101, 3'b110: pp = -mcand_q;
            default:        pp = '0;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            busy_o   <= 1'b0;
            done_o   <= 1'b0;
            cnt_q    <= '0;
            mcand_q  <= '0;
            mplier_q <= '0;
            acc_q    <= '0;
        end else begin
            done_o <= 1'b0;
            if (!busy_o) begin
                if (start_i) begin
                    busy_o   <= 1'b1;
                    cnt_q    <= CntW'(Width / 2);
                    mcand_q  <= {{Width{a_i[Width-1]}}, a_i};
                    mplier_q <= {b_i, 1'b0};
                    acc_q    <= '0;
                end
            end else begin
                acc_q    <= acc_q + pp;
                mcand_q  <= mcand_q << 2;
                mplier_q <= {2'b00, mplier_q[Width:2]};
                cnt_q    <= cnt_q - 1'b1;
                if (cnt_q == 1) begin
                    busy_o <= 1'b0;
                    done_o <= 1'b1;
                end
            end
        end
    end

    assign product_o = acc_q;
endmodule
