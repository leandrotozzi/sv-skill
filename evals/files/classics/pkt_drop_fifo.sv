// Reference store-and-forward packet FIFO (only used to validate pkt_drop_fifo_tb.sv).
// Unreset RAM written at wr_ptr; wr_cmt marks the end of the last good packet, so
// the read side only ever sees whole good packets. A bad packet rolls wr_ptr back
// to wr_cmt at its tlast; a packet that reaches Depth + 1 beats rolls back at once
// and the rest of it is discarded. The read port is registered (RAM read with
// enable) and its register is the output stage.
module pkt_drop_fifo #(
    parameter int Depth = 64
) (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        s_tvalid_i,
    output logic        s_tready_o,
    input  logic [31:0] s_tdata_i,
    input  logic        s_tlast_i,
    input  logic        s_tuser_i,
    output logic        m_tvalid_o,
    input  logic        m_tready_i,
    output logic [31:0] m_tdata_o,
    output logic        m_tlast_o,
    output logic [15:0] drop_cnt_o
);
    if (Depth < 16 || Depth > 4096 || (Depth & (Depth - 1)) != 0) begin : g_bad_depth
        $error("pkt_drop_fifo: Depth must be a power of two from 16 to 4096");
    end

    localparam int AW = $clog2(Depth);

    logic [32:0] mem [Depth];          // {tlast, tdata}
    logic [32:0] rdata;
    logic [AW:0] wr_ptr, wr_cmt, rd_ptr;
    logic        ovf;                  // discarding the rest of a too-long packet

    wire [AW:0] used    = wr_ptr - rd_ptr;
    wire [AW:0] cur_len = wr_ptr - wr_cmt;
    wire        discard = ovf || cur_len == Depth;  // this beat makes or keeps it too long
    wire        push    = s_tvalid_i && s_tready_o;
    wire        load    = rd_ptr != wr_cmt && (!m_tvalid_o || m_tready_i);

    assign s_tready_o = discard || used != Depth;
    assign m_tdata_o  = rdata[31:0];
    assign m_tlast_o  = rdata[32];

    always_ff @(posedge clk_i) begin
        if (push && !discard) mem[wr_ptr[AW-1:0]] <= {s_tlast_i, s_tdata_i};
        if (load) rdata <= mem[rd_ptr[AW-1:0]];
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            wr_ptr     <= '0;
            wr_cmt     <= '0;
            rd_ptr     <= '0;
            ovf        <= 1'b0;
            m_tvalid_o <= 1'b0;
            drop_cnt_o <= '0;
        end else begin
            if (push) begin
                if (discard) begin
                    wr_ptr <= wr_cmt;
                    ovf    <= !s_tlast_i;
                    if (s_tlast_i) drop_cnt_o <= drop_cnt_o + 1'b1;
                end else if (s_tlast_i && s_tuser_i) begin
                    wr_ptr     <= wr_cmt;
                    drop_cnt_o <= drop_cnt_o + 1'b1;
                end else if (s_tlast_i) begin
                    wr_ptr <= wr_ptr + 1'b1;
                    wr_cmt <= wr_ptr + 1'b1;
                end else begin
                    wr_ptr <= wr_ptr + 1'b1;
                end
            end
            if (load) begin
                rd_ptr     <= rd_ptr + 1'b1;
                m_tvalid_o <= 1'b1;
            end else if (m_tready_i) begin
                m_tvalid_o <= 1'b0;
            end
        end
    end
endmodule
