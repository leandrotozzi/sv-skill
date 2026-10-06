// Reference AXI4-Lite register block (only used to validate axil_regs_tb).
// AW and W are taken independently and held until both are in; the write is
// done in the cycle the second arrives and bvalid_o rises the next cycle.
// Readies are low only while the write (or read) is in progress.
module axil_regs (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        awvalid_i,
    output logic        awready_o,
    input  logic [7:0]  awaddr_i,
    input  logic        wvalid_i,
    output logic        wready_o,
    input  logic [31:0] wdata_i,
    input  logic [3:0]  wstrb_i,
    output logic        bvalid_o,
    input  logic        bready_i,
    output logic [1:0]  bresp_o,
    input  logic        arvalid_i,
    output logic        arready_o,
    input  logic [7:0]  araddr_i,
    output logic        rvalid_o,
    input  logic        rready_i,
    output logic [31:0] rdata_o,
    output logic [1:0]  rresp_o
);
    logic [31:0] regs [3];
    logic        aw_got, w_got;
    logic [7:0]  aw_addr_q;
    logic [31:0] w_data_q;
    logic [3:0]  w_strb_q;

    assign awready_o = !aw_got && !bvalid_o;
    assign wready_o  = !w_got && !bvalid_o;
    assign arready_o = !rvalid_o;

    wire         aw_hs = awvalid_i && awready_o;
    wire         w_hs  = wvalid_i && wready_o;
    wire [7:0]   wa    = aw_got ? aw_addr_q : awaddr_i;
    wire [31:0]  wd    = w_got ? w_data_q : wdata_i;
    wire [3:0]   ws    = w_got ? w_strb_q : wstrb_i;
    wire         do_wr = (aw_got || aw_hs) && (w_got || w_hs);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            regs      <= '{default: '0};
            aw_got    <= 1'b0;
            w_got     <= 1'b0;
            aw_addr_q <= '0;
            w_data_q  <= '0;
            w_strb_q  <= '0;
            bvalid_o  <= 1'b0;
            bresp_o   <= 2'b00;
        end else begin
            if (bvalid_o && bready_i) bvalid_o <= 1'b0;
            if (aw_hs) begin
                aw_got    <= 1'b1;
                aw_addr_q <= awaddr_i;
            end
            if (w_hs) begin
                w_got    <= 1'b1;
                w_data_q <= wdata_i;
                w_strb_q <= wstrb_i;
            end
            if (do_wr) begin
                aw_got   <= 1'b0;
                w_got    <= 1'b0;
                bvalid_o <= 1'b1;
                bresp_o  <= (wa >= 8'h10) ? 2'b10 : 2'b00;
                if (wa < 8'h0C)
                    for (int b = 0; b < 4; b++)
                        if (ws[b]) regs[wa[3:2]][8*b +: 8] <= wd[8*b +: 8];
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rvalid_o <= 1'b0;
            rdata_o  <= '0;
            rresp_o  <= 2'b00;
        end else begin
            if (rvalid_o && rready_i) rvalid_o <= 1'b0;
            if (arvalid_i && arready_o) begin
                rvalid_o <= 1'b1;
                rresp_o  <= (araddr_i >= 8'h10) ? 2'b10 : 2'b00;
                rdata_o  <= (araddr_i < 8'h0C) ? regs[araddr_i[3:2]] :
                            (araddr_i < 8'h10) ? 32'h5EC0_0001 : 32'h0;
            end
        end
    end
endmodule
