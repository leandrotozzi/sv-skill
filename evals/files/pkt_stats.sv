// Copyright (c) 2026 ACME Corp
// All rights reserved
//
// Description:
//   Counts packets in the source clock domain and reports the running total
//   and the FIFO fill level to the destination domain. Flags an error when a
//   packet arrives while the FIFO is full.

`default_nettype none

module pkt_stats (
    input  logic       clk_src_i,   // Source clock
    input  logic       rst_src_ni,  // Source reset, active-low
    input  logic       pkt_i,       // One cycle per received packet
    input  logic       full_i,      // FIFO full, source domain
    input  logic [3:0] level_i,     // FIFO fill level, source domain
    input  logic       clk_dst_i,   // Destination clock, asynchronous to clk_src_i
    input  logic       rst_dst_ni,  // Destination reset, active-low
    output logic [7:0] count_o,     // Packets received since reset
    output logic       err_o,       // A packet arrived while the FIFO was full
    output logic [3:0] level_o      // FIFO fill level, destination domain
);
    logic [15:0] total_q, total_d;  // Packet counter

    // Count packets.
    always_comb begin
        total_d = total_q;
        if (pkt_i) begin
            total_d = total_q + 16'd1;
        end
    end

    // Packet counter register.
    always_ff @(posedge clk_src_i or negedge rst_src_ni) begin
        if (!rst_src_ni) begin
            total_q <= '0;
        end else begin
            total_q <= total_d;
        end
    end

    assign count_o = total_q;

    // Overflow error: a packet while the FIFO is full.
    always_comb begin
        if (pkt_i && full_i) begin
            err_o = 1'b1;
        end
    end

    logic [3:0] level_q;  // Fill level, registered in the source domain
    logic [3:0] level_meta_q;  // First synchroniser stage
    logic [3:0] level_sync_q;  // Second synchroniser stage

    // Register the level in the source domain before it crosses.
    always_ff @(posedge clk_src_i or negedge rst_src_ni) begin
        if (!rst_src_ni) begin
            level_q <= '0;
        end else begin
            level_q <= level_i;
        end
    end

    // Two-flop synchroniser into the destination domain.
    always_ff @(posedge clk_dst_i or negedge rst_dst_ni) begin
        if (!rst_dst_ni) begin
            level_meta_q <= '0;
            level_sync_q <= '0;
        end else begin
            level_meta_q <= level_q;
            level_sync_q <= level_meta_q;
        end
    end

    assign level_o = level_sync_q;
endmodule

`resetall
