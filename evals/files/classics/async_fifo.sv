// Reference dual-clock FIFO (only used to validate async_fifo_tb.sv).
// Gray pointers with a wrap bit, two-flop synchronisers, registered flags,
// first-word-fall-through read port.
module async_fifo #(
    parameter int Width = 8,
    parameter int Depth = 16
) (
    input  logic             wclk_i,
    input  logic             wrst_ni,
    input  logic             wvalid_i,
    input  logic [Width-1:0] wdata_i,
    output logic             wfull_o,
    input  logic             rclk_i,
    input  logic             rrst_ni,
    output logic             rvalid_o,
    input  logic             rready_i,
    output logic [Width-1:0] rdata_o
);
    localparam int Aw = $clog2(Depth);

    if (Depth < 4 || (Depth & (Depth - 1)) != 0) begin : g_bad_depth
        $error("async_fifo: Depth must be a power of two and at least 4");
    end

    function automatic logic [Aw:0] b2g(logic [Aw:0] b);
        return b ^ (b >> 1);
    endfunction

    logic [Width-1:0] mem[Depth];
    logic [Aw:0] wbin, wgray, rbin, rgray;
    logic [Aw:0] rgray_q1, rgray_q2;  // read pointer in the write domain
    logic [Aw:0] wgray_q1, wgray_q2;  // write pointer in the read domain

    // Write side.
    logic        wpush;
    logic [Aw:0] wbin_n, wgray_n;
    assign wpush   = wvalid_i & ~wfull_o;
    assign wbin_n  = wbin + (Aw + 1)'(wpush);
    assign wgray_n = b2g(wbin_n);

    always_ff @(posedge wclk_i or negedge wrst_ni) begin
        if (!wrst_ni) begin
            wbin     <= '0;
            wgray    <= '0;
            wfull_o  <= 1'b0;
            rgray_q1 <= '0;
            rgray_q2 <= '0;
        end else begin
            wbin     <= wbin_n;
            wgray    <= wgray_n;
            wfull_o  <= wgray_n == {~rgray_q2[Aw:Aw-1], rgray_q2[Aw-2:0]};
            rgray_q1 <= rgray;
            rgray_q2 <= rgray_q1;
        end
    end

    always_ff @(posedge wclk_i) begin
        if (wpush) mem[wbin[Aw-1:0]] <= wdata_i;
    end

    // Read side.
    logic        rpop;
    logic [Aw:0] rbin_n, rgray_n;
    assign rpop    = rvalid_o & rready_i;
    assign rbin_n  = rbin + (Aw + 1)'(rpop);
    assign rgray_n = b2g(rbin_n);

    always_ff @(posedge rclk_i or negedge rrst_ni) begin
        if (!rrst_ni) begin
            rbin     <= '0;
            rgray    <= '0;
            rvalid_o <= 1'b0;
            wgray_q1 <= '0;
            wgray_q2 <= '0;
        end else begin
            rbin     <= rbin_n;
            rgray    <= rgray_n;
            rvalid_o <= rgray_n != wgray_q2;
            wgray_q1 <= wgray;
            wgray_q2 <= wgray_q1;
        end
    end

    assign rdata_o = mem[rbin[Aw-1:0]];
endmodule
