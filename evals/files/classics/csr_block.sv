// Reference register block: CTRL (RW enable mask), STATUS (sticky events,
// write-1-to-clear, set wins), COUNT (RO event-cycle counter), SCRATCH (RW).
module csr_block (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        req_i,
    input  logic        we_i,
    input  logic [3:0]  addr_i,
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,
    input  logic [7:0]  event_i,
    output logic        irq_o
);
    logic [7:0]  enable_q, status_q;
    logic [31:0] count_q, scratch_q;
    logic        wr;

    assign wr    = req_i && we_i;
    assign irq_o = |(status_q & enable_q);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            enable_q  <= '0;
            status_q  <= '0;
            count_q   <= '0;
            scratch_q <= '0;
            rdata_o   <= '0;
        end else begin
            if (wr && addr_i[3:2] == 2'd0) enable_q <= wdata_i[7:0];
            status_q <= (status_q & ~((wr && addr_i[3:2] == 2'd1) ? wdata_i[7:0] : 8'h00)) | event_i;
            if (|event_i) count_q <= count_q + 1;
            if (wr && addr_i[3:2] == 2'd3) scratch_q <= wdata_i;
            if (req_i && !we_i) begin
                case (addr_i[3:2])
                    2'd0: rdata_o <= {24'h0, enable_q};
                    2'd1: rdata_o <= {24'h0, status_q};
                    2'd2: rdata_o <= count_q;
                    2'd3: rdata_o <= scratch_q;
                endcase
            end
        end
    end
endmodule
