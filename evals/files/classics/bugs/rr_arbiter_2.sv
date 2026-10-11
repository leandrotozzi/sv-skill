// Reference round-robin arbiter: combinational one-hot grant to the first
// requester at or after prio_q (wrapping); prio_q moves to winner + 1.
// Planted bug 2: search starts after the priority index.
module rr_arbiter #(
    parameter int NumReq = 4
) (
    input  logic              clk_i,
    input  logic              rst_ni,
    input  logic [NumReq-1:0] req_i,
    output logic [NumReq-1:0] gnt_o
);
    localparam int IdxW = (NumReq > 1) ? $clog2(NumReq) : 1;

    logic [IdxW-1:0] prio_q, prio_d;

    always_comb begin
        gnt_o  = '0;
        prio_d = prio_q;
        // Scan from the highest offset down so the smallest offset wins.
        for (int k = NumReq - 1; k >= 0; k--) begin
            int idx;
            idx = (int'(prio_q) + k + 1) % NumReq;
            if (req_i[idx]) begin
                gnt_o      = '0;
                gnt_o[idx] = 1'b1;
                prio_d     = IdxW'((idx + 1) % NumReq);
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) prio_q <= '0;
        else         prio_q <= prio_d;
    end
endmodule
