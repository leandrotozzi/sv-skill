// Reference 8N1 UART receiver: 2-flop synchroniser, mid-bit sampling, start
// glitch rejection, then wait for an idle-high line before the next frame.
module uart_rx #(
    parameter int ClksPerBit = 16
) (
    input  logic       clk_i,
    input  logic       rst_ni,
    input  logic       rx_i,
    output logic       valid_o,
    output logic [7:0] data_o,
    output logic       frame_err_o
);
    localparam int CntW = $clog2(ClksPerBit + 1);

    typedef enum logic [2:0] {WaitHigh, Idle, Start, Data, Stop} state_e;

    state_e          state_q;
    logic [1:0]      sync_q;
    logic            rx;
    logic [CntW-1:0] cnt_q;
    logic [2:0]      bit_q;
    logic [7:0]      shift_q;

    assign rx = sync_q[1];

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            sync_q      <= 2'b11;
            state_q     <= WaitHigh;
            cnt_q       <= '0;
            bit_q       <= '0;
            shift_q     <= '0;
            data_o      <= '0;
            valid_o     <= 1'b0;
            frame_err_o <= 1'b0;
        end else begin
            sync_q      <= {sync_q[0], rx_i};
            valid_o     <= 1'b0;
            frame_err_o <= 1'b0;
            cnt_q       <= cnt_q + 1'b1;
            case (state_q)
                WaitHigh: if (rx) state_q <= Idle;
                Idle: if (!rx) begin
                    state_q <= Start;
                    cnt_q   <= '0;
                end
                // cnt_q counts clocks since the falling edge was seen.
                Start: if (cnt_q == CntW'(ClksPerBit / 2 - 1)) begin
                    cnt_q   <= '0;
                    bit_q   <= '0;
                    state_q <= rx ? Idle : Data;  // high at mid-bit: glitch
                end
                Data: if (cnt_q == CntW'(ClksPerBit - 1)) begin
                    cnt_q   <= '0;
                    shift_q <= {rx, shift_q[7:1]};
                    bit_q   <= bit_q + 1'b1;
                    if (bit_q == 3'd7) state_q <= Stop;
                end
                Stop: if (cnt_q == CntW'(ClksPerBit - 1)) begin
                    if (rx) begin
                        valid_o <= 1'b1;
                        data_o  <= shift_q;
                    end else begin
                        frame_err_o <= 1'b1;
                    end
                    state_q <= WaitHigh;
                end
                default: state_q <= WaitHigh;
            endcase
        end
    end
endmodule
