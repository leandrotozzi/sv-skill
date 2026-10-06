// Reference AXI-Stream 32-to-8 downsizer (only used to validate axis_downsizer_tb).
module axis_downsizer (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        s_tvalid_i,
    output logic        s_tready_o,
    input  logic [31:0] s_tdata_i,
    input  logic [3:0]  s_tkeep_i,
    input  logic        s_tlast_i,
    output logic        m_tvalid_o,
    input  logic        m_tready_i,
    output logic [7:0]  m_tdata_o,
    output logic        m_tlast_o
);
    logic [31:0] data_q;
    logic [2:0]  left_q;  // bytes still to send
    logic        last_q;

    assign m_tvalid_o = left_q != 0;
    assign m_tdata_o  = data_q[7:0];
    assign m_tlast_o  = last_q && left_q == 1;
    assign s_tready_o = left_q == 0 || (left_q == 1 && m_tready_i);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            data_q <= '0;
            left_q <= '0;
            last_q <= 1'b0;
        end else if (s_tvalid_i && s_tready_o) begin
            data_q <= s_tdata_i;
            left_q <= 3'(s_tkeep_i[0]) + 3'(s_tkeep_i[1]) + 3'(s_tkeep_i[2]) + 3'(s_tkeep_i[3]);
            last_q <= s_tlast_i;
        end else if (m_tvalid_o && m_tready_i) begin
            data_q <= data_q >> 8;
            left_q <= left_q - 1;
        end
    end
endmodule
