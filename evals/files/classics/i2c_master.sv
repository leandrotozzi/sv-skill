// Reference byte-level I2C master (only used to validate i2c_master_tb.sv).
// Each bit is a low phase (SDA set one cycle after SCL falls, SCL released
// ClkDiv cycles after the phase starts) and a high phase (wait for scl_i,
// then ClkDiv cycles counting the first one seen high). START from idle pulls
// SDA, then SCL ClkDiv cycles later; a repeated START releases SDA in a low
// phase and pulls it in the middle of the high phase. STOP pulls SDA in a low
// phase, releases it at the end of the high phase and waits ClkDiv more
// cycles (bus free) before answering.
module i2c_master #(
    parameter int ClkDiv = 250
) (
    input  logic       clk_i,
    input  logic       rst_ni,
    input  logic       cmd_valid_i,
    output logic       cmd_ready_o,
    input  logic [1:0] cmd_i,
    input  logic [7:0] wdata_i,
    input  logic       ack_i,
    output logic       rsp_valid_o,
    output logic [7:0] rdata_o,
    output logic       nack_o,
    input  logic       scl_i,
    output logic       scl_oe_o,
    input  logic       sda_i,
    output logic       sda_oe_o
);
    if (ClkDiv < 4) begin : g_bad_clkdiv
        $error("i2c_master: ClkDiv must be at least 4");
    end

    localparam logic [1:0] CmdStart = 2'd0, CmdStop = 2'd1, CmdRead = 2'd3;
    localparam logic [15:0] Last = 16'(ClkDiv - 1);
    localparam logic [15:0] Mid = 16'(ClkDiv / 2 - 1);

    typedef enum logic [2:0] {Idle, Held, Hold, Low, Rise, High, Free} state_e;

    state_e      state;
    logic [1:0]  cmd;
    logic [15:0] cnt;
    logic [3:0]  bitn;
    logic [7:0]  tx, rx;
    logic        ack_q;
    logic        low_sda;

    assign cmd_ready_o = state == Idle || state == Held;

    // SDA pull for the low phase of the current bit.
    always_comb begin
        case (cmd)
            CmdStart: low_sda = 1'b0;
            CmdStop:  low_sda = 1'b1;
            CmdRead:  low_sda = bitn == 4'd8 ? ack_q : 1'b0;
            default:  low_sda = bitn == 4'd8 ? 1'b0 : !tx[3'(7 - bitn)];
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state       <= Idle;
            cmd         <= '0;
            cnt         <= '0;
            bitn        <= '0;
            tx          <= '0;
            rx          <= '0;
            ack_q       <= 1'b0;
            scl_oe_o    <= 1'b0;
            sda_oe_o    <= 1'b0;
            rsp_valid_o <= 1'b0;
            rdata_o     <= '0;
            nack_o      <= 1'b0;
        end else begin
            rsp_valid_o <= 1'b0;
            case (state)
                Idle, Held: begin
                    if (cmd_valid_i) begin
                        cmd   <= cmd_i;
                        tx    <= wdata_i;
                        ack_q <= ack_i;
                        bitn  <= '0;
                        cnt   <= '0;
                        if (cmd_i == CmdStart && state == Idle) begin
                            sda_oe_o <= 1'b1;
                            state    <= Hold;
                        end else begin
                            state <= Low;
                        end
                    end
                end
                Hold: begin
                    if (cnt == Last) begin
                        scl_oe_o    <= 1'b1;
                        rsp_valid_o <= 1'b1;
                        state       <= Held;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end
                Low: begin
                    if (cnt == '0) sda_oe_o <= low_sda;
                    if (cnt == Last) begin
                        scl_oe_o <= 1'b0;
                        state    <= Rise;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end
                Rise: begin
                    if (scl_i) begin
                        cnt   <= 16'd1;
                        state <= High;
                    end
                end
                High: begin
                    if (cmd == CmdStart && cnt == Mid) sda_oe_o <= 1'b1;
                    if (cnt == Last) begin
                        case (cmd)
                            CmdStop: begin
                                sda_oe_o <= 1'b0;
                                cnt      <= '0;
                                state    <= Free;
                            end
                            CmdStart: begin
                                scl_oe_o    <= 1'b1;
                                rsp_valid_o <= 1'b1;
                                state       <= Held;
                            end
                            default: begin
                                scl_oe_o <= 1'b1;
                                if (bitn == 4'd8) begin
                                    nack_o      <= sda_i;
                                    rdata_o     <= rx;
                                    rsp_valid_o <= 1'b1;
                                    state       <= Held;
                                end else begin
                                    rx    <= {rx[6:0], sda_i};
                                    bitn  <= bitn + 1'b1;
                                    cnt   <= '0;
                                    state <= Low;
                                end
                            end
                        endcase
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end
                Free: begin
                    if (cnt == Last) begin
                        rsp_valid_o <= 1'b1;
                        state       <= Idle;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end
                default: state <= Idle;
            endcase
        end
    end
endmodule
