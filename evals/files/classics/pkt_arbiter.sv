// Reference packet arbiter (only used to validate pkt_arbiter_tb.sv).
// Combinational mux: the round-robin choice is locked as soon as a first beat
// is offered and released when the tlast beat is sent.
module pkt_arbiter #(
    parameter int NumIn     = 4,
    parameter int DataWidth = 16
) (
    input  logic                       clk_i,
    input  logic                       rst_ni,
    input  logic [NumIn-1:0]           s_tvalid_i,
    output logic [NumIn-1:0]           s_tready_o,
    input  logic [NumIn*DataWidth-1:0] s_tdata_i,
    input  logic [NumIn-1:0]           s_tlast_i,
    output logic                       m_tvalid_o,
    input  logic                       m_tready_i,
    output logic [DataWidth-1:0]       m_tdata_o,
    output logic                       m_tlast_o,
    output logic [$clog2(NumIn)-1:0]   m_tid_o
);
    localparam int IdW = $clog2(NumIn);

    logic           busy_q;
    logic [IdW-1:0] cur_q, last_q, pick;

    always_comb begin
        pick = cur_q;
        if (!busy_q) begin
            // First valid input after last_q, wrapping (last_q itself comes last).
            for (int k = NumIn; k >= 1; k--) begin
                int idx;
                idx = (int'(last_q) + k) % NumIn;
                if (s_tvalid_i[idx]) pick = IdW'(idx);
            end
        end
        m_tvalid_o = s_tvalid_i[pick];
        m_tdata_o  = s_tdata_i[pick*DataWidth+:DataWidth];
        m_tlast_o  = s_tlast_i[pick];
        m_tid_o    = pick;
        s_tready_o = '0;
        s_tready_o[pick] = m_tready_i;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            busy_q <= 1'b0;
            cur_q  <= '0;
            last_q <= IdW'(NumIn - 1);
        end else if (m_tvalid_o) begin
            busy_q <= !(m_tready_i && m_tlast_o);
            cur_q  <= pick;
            last_q <= pick;
        end
    end
endmodule
