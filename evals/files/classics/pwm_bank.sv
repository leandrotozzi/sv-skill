// Copyright (c) 2026 <Company>
// All rights reserved
//
// Description:
//   Reference for eval 128: a bank of Channels PWM outputs driven by one
//   shared counter that runs 0..P, so a PWM period lasts P+1 cycles. A load
//   writes a pending period and duty set; the active set takes it only when
//   the counter wraps from P to 0, a load in the wrap cycle included.

`default_nettype none

module pwm_bank #(
    parameter int Channels = 4,  // number of PWM channels, at least 1
    parameter int Width    = 8   // counter, period and duty width, 2 to 16
) (
    input  logic                      clk_i,     // clock
    input  logic                      rst_ni,    // asynchronous reset, active low
    input  logic                      load_i,    // store period_i and duty_i as pending
    input  logic [         Width-1:0] period_i,  // new last counter value P
    input  logic [Channels*Width-1:0] duty_i,    // new duties, channel c at c*Width
    output logic [      Channels-1:0] pwm_o,     // high while cnt < active duty
    output logic                      sync_o     // high while cnt == 0
);
    logic [         Width-1:0] cnt_q;  // shared counter, 0..per_q
    logic [         Width-1:0] per_q;  // active period P
    logic [         Width-1:0] per_pend_q;  // pending period
    logic [Channels*Width-1:0] duty_q;  // active duties
    logic [Channels*Width-1:0] duty_pend_q;  // pending duties
    logic                      pend_q;  // a load happened since the last wrap
    logic                      wrap;  // counter wraps from P to 0 this cycle

    assign wrap = cnt_q == per_q;

    // Counter, pending set and the swap to the active set at the wrap.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            cnt_q       <= '0;
            per_q       <= '0;
            per_pend_q  <= '0;
            duty_q      <= '0;
            duty_pend_q <= '0;
            pend_q      <= 1'b0;
        end else begin
            cnt_q <= wrap ? '0 : cnt_q + 1'b1;
            if (load_i) begin
                per_pend_q  <= period_i;
                duty_pend_q <= duty_i;
            end
            if (wrap && load_i) begin
                per_q  <= period_i;  // a load in the wrap cycle is taken at once
                duty_q <= duty_i;
            end else if (wrap && pend_q) begin
                per_q  <= per_pend_q;
                duty_q <= duty_pend_q;
            end
            if (wrap) begin
                pend_q <= 1'b0;
            end else if (load_i) begin
                pend_q <= 1'b1;
            end
        end
    end

    // Per-channel duty compare on registered state only.
    always_comb begin
        for (int c = 0; c < Channels; c++) begin
            pwm_o[c] = cnt_q < duty_q[c*Width+:Width];
        end
    end

    assign sync_o = cnt_q == '0;
endmodule

`resetall
