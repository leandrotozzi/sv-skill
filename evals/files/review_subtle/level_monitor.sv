// Copyright (c) 2026 ACME Corp
// All rights reserved
//
// Description:
//   Watches a stream of two's-complement ADC samples. Each sample is
//   corrected by a small positive bias; a sample whose corrected magnitude
//   exceeds Thresh is an event. Events are counted, and the monitor's
//   activity is reported, in the slower configuration clock domain.

`default_nettype none

module level_monitor #(
    parameter logic [11:0] Thresh = 12'd1500  // Event threshold, magnitude
) (
    input  logic        clk_smp_i,      // Sample clock, 200 MHz
    input  logic        clk_cfg_i,      // Configuration clock, 25 MHz, asynchronous to clk_smp_i
    input  logic        rst_ni,         // Chip reset from the pad, asynchronous, active-low
    input  logic        enable_i,       // Monitor enable, sample domain
    input  logic        bypass_i,       // Bypass the monitor, sample domain
    input  logic [11:0] sample_i,       // ADC sample, two's complement
    input  logic [ 3:0] bias_i,         // Bias added to every sample, 0 to 15
    output logic [ 7:0] event_count_o,  // Events since reset, configuration domain
    output logic        active_o        // Monitor enabled and not bypassed, configuration domain
);
    // --- Sample domain ---

    logic [11:0] corrected_d, corrected_q;  // Sample plus bias
    logic over_d, over_q;  // Corrected sample beyond the threshold, one cycle per sample
    logic enable_q;  // Registered enable

    // Correct the sample and compare its magnitude with the threshold.
    always_comb begin
        corrected_d = sample_i + {8'd0, bias_i};
        over_d = (corrected_q > Thresh) || (corrected_q < -Thresh);
    end

    // Sample-domain registers.
    always_ff @(posedge clk_smp_i or negedge rst_ni) begin
        if (!rst_ni) begin
            corrected_q <= '0;
            over_q <= 1'b0;
            enable_q <= 1'b0;
        end else begin
            corrected_q <= corrected_d;
            over_q <= over_d && enable_q;
            enable_q <= enable_i;
        end
    end

    logic active;  // Monitor enabled and not bypassed

    assign active = enable_q && !bypass_i;

    // --- Crossing into the configuration domain ---

    logic over_meta_q, over_sync_q;  // Event synchroniser
    logic active_meta_q, active_sync_q;  // Activity synchroniser

    // Two-flop synchronisers.
    always_ff @(posedge clk_cfg_i or negedge rst_ni) begin
        if (!rst_ni) begin
            over_meta_q   <= 1'b0;
            over_sync_q   <= 1'b0;
            active_meta_q <= 1'b0;
            active_sync_q <= 1'b0;
        end else begin
            over_meta_q   <= over_q;
            over_sync_q   <= over_meta_q;
            active_meta_q <= active;
            active_sync_q <= active_meta_q;
        end
    end

    // --- Configuration domain ---

    logic [7:0] count_d, count_q;  // Event counter, saturating

    // Count one event per synchronised event cycle, saturating at 255.
    always_comb begin
        count_d = count_q;
        if (over_sync_q && count_q != 8'hff) begin
            count_d = count_q + 8'd1;
        end
    end

    // Event counter register.
    always_ff @(posedge clk_cfg_i or negedge rst_ni) begin
        if (!rst_ni) begin
            count_q <= '0;
        end else begin
            count_q <= count_d;
        end
    end

    assign event_count_o = count_q;
    assign active_o = active_sync_q;
endmodule

`resetall
