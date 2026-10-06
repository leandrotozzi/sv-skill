// Reference first-word-fall-through FIFO (only used to validate fwft_fifo_tb.sv).
// Unreset RAM with a registered read port, then a two-entry output buffer that the
// RAM prefetches into, so the head word is always ready when the previous one leaves.
module fwft_fifo #(
    parameter int Width = 32,
    parameter int Depth = 512
) (
    input  logic                   clk_i,
    input  logic                   rst_ni,
    input  logic                   in_valid_i,
    output logic                   in_ready_o,
    input  logic [Width-1:0]       in_data_i,
    output logic                   out_valid_o,
    input  logic                   out_ready_i,
    output logic [Width-1:0]       out_data_o,
    output logic [$clog2(Depth):0] count_o
);
    localparam int AW = $clog2(Depth);

    logic [Width-1:0] mem [Depth];
    logic [Width-1:0] rdata;
    logic [AW-1:0]    wr_ptr, rd_ptr;
    logic [AW:0]      ram_cnt;     // words in the RAM not yet read out
    logic             rd_valid;    // rdata holds a word read on the last edge
    logic [Width-1:0] ob0, ob1;    // output buffer, ob0 is the head
    logic [1:0]       ob_cnt;

    wire push  = in_valid_i && in_ready_o;
    wire pop   = out_valid_o && out_ready_i;
    // Read when the word will find room in the output buffer on the following edge.
    wire issue = ram_cnt != 0 && (ob_cnt + rd_valid - pop) < 2;

    assign in_ready_o  = count_o < Depth;
    assign out_valid_o = ob_cnt != 0;
    assign out_data_o  = ob0;

    always_ff @(posedge clk_i) begin
        if (push) mem[wr_ptr] <= in_data_i;
        if (issue) rdata <= mem[rd_ptr];
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            wr_ptr   <= '0;
            rd_ptr   <= '0;
            ram_cnt  <= '0;
            rd_valid <= 1'b0;
            ob_cnt   <= '0;
            count_o  <= '0;
            ob0      <= '0;
            ob1      <= '0;
        end else begin
            if (push) wr_ptr <= wr_ptr + 1'b1;
            if (issue) rd_ptr <= rd_ptr + 1'b1;
            ram_cnt  <= ram_cnt + push - issue;
            rd_valid <= issue;
            count_o  <= count_o + push - pop;
            // Shift out the head on pop, append the RAM word if one arrived.
            if (pop) ob0 <= ob1;
            if (rd_valid) begin
                if (ob_cnt - pop == 0) ob0 <= rdata;
                else ob1 <= rdata;
            end
            ob_cnt <= ob_cnt + rd_valid - pop;
        end
    end
endmodule
