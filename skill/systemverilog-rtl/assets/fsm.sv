// Copyright (c) 2026 <Company>
// All rights reserved
//
// Description:
//   Canonical FSM: grants one request at a time after a fixed wait. State in
//   a typedef enum, state_q/state_d, unique case with default, registered
//   outputs so no combinational path leaves the module.

`default_nettype none

`include "assert_macros.svh"

module fsm #(
    parameter int unsigned WaitCycles = 4  // Cycles between request and grant; at least 1
) (
    input  logic clk_i,   // System clock
    input  logic rst_ni,  // Asynchronous reset, active-low
    input  logic req_i,   // Requester wants the resource; held until grant_o
    input  logic done_i,  // Requester releases the resource
    output logic grant_o  // Resource granted; registered
);
    localparam int unsigned CountW = $clog2(WaitCycles + 1);  // Bits to count to WaitCycles

    // WaitCycles must be positive: a zero wait makes StWait unreachable.
    if (WaitCycles < 1) begin : gen_wait_check
        $error("WaitCycles must be at least 1");
    end

    fsm_pkg::state_e state_q, state_d;  // Handshake state
    logic [CountW-1:0] count_q, count_d;  // Cycles spent in StWait
    logic grant_q, grant_d;  // Registered grant

    // Next state, wait counter and grant.
    always_comb begin
        state_d = state_q;
        count_d = count_q;
        grant_d = grant_q;
        unique case (state_q)
            // Wait for a request.
            fsm_pkg::StIdle: begin
                if (req_i) begin
                    state_d = fsm_pkg::StWait;
                    count_d = '0;
                end
            end
            // Count WaitCycles before granting.
            fsm_pkg::StWait: begin
                count_d = count_q + 1'b1;
                if (count_q == CountW'(WaitCycles - 1)) begin
                    state_d = fsm_pkg::StGrant;
                    grant_d = 1'b1;
                end
            end
            // Hold the grant until the requester is done.
            fsm_pkg::StGrant: begin
                if (done_i) begin
                    state_d = fsm_pkg::StIdle;
                    grant_d = 1'b0;
                end
            end
            default: begin
                state_d = fsm_pkg::StIdle;
                grant_d = 1'b0;
            end
        endcase
    end

    // State, counter and grant registers.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= fsm_pkg::StIdle;
            count_q <= '0;
            grant_q <= 1'b0;
        end else begin
            state_q <= state_d;
            count_q <= count_d;
            grant_q <= grant_d;
        end
    end

    assign grant_o = grant_q;

    // The output is never X once out of reset (VER-002).
    `ASSERT_KNOWN(GrantKnown_A, grant_o)
endmodule

`resetall
