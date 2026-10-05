// Reference radix-2 restoring divider. Start edge captures the operands; Width
// iteration edges follow; the last one drops busy_o and raises done_o for one
// cycle. Divisor 0 naturally yields quotient all ones, remainder = dividend.
module divider #(
    parameter int Width = 16
) (
    input  logic             clk_i,
    input  logic             rst_ni,
    input  logic             start_i,
    input  logic [Width-1:0] dividend_i,
    input  logic [Width-1:0] divisor_i,
    output logic             busy_o,
    output logic             done_o,
    output logic [Width-1:0] quotient_o,
    output logic [Width-1:0] remainder_o
);
    localparam int CntW = $clog2(Width + 1);

    logic [CntW-1:0]  cnt_q;
    logic [Width-1:0] dsor_q, quot_q, rem_q;
    logic [Width:0]   trial;
    logic             fits;

    // One restoring step: shift in the next dividend bit (MSB of quot_q).
    assign trial = {rem_q, quot_q[Width-1]};
    assign fits  = trial >= {1'b0, dsor_q};

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            busy_o <= 1'b0;
            done_o <= 1'b0;
            cnt_q  <= '0;
            dsor_q <= '0;
            quot_q <= '0;
            rem_q  <= '0;
        end else begin
            done_o <= 1'b0;
            if (!busy_o) begin
                if (start_i) begin
                    busy_o <= 1'b1;
                    cnt_q  <= CntW'(Width);
                    dsor_q <= divisor_i;
                    quot_q <= dividend_i;  // dividend bits shift out as quotient bits shift in
                    rem_q  <= '0;
                end
            end else begin
                rem_q  <= fits ? Width'(trial - {1'b0, dsor_q}) : trial[Width-1:0];
                quot_q <= {quot_q[Width-2:0], fits};
                cnt_q  <= cnt_q - 1'b1;
                if (cnt_q == 1) begin
                    busy_o <= 1'b0;
                    done_o <= 1'b1;
                end
            end
        end
    end

    assign quotient_o  = quot_q;
    assign remainder_o = rem_q;
endmodule
