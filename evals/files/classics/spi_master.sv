// Reference SPI master (only used to validate spi_master_tb.sv).
// The start edge drops cs_no and sets sclk_o to the new cpol; after ClkDiv
// cycles come 16 edges ClkDiv cycles apart, then ClkDiv cycles later cs_no
// rises and the next cycle pulses done_o.
module spi_master #(
    parameter int ClkDiv = 4
) (
    input  logic       clk_i,
    input  logic       rst_ni,
    input  logic       start_i,
    input  logic       cpol_i,
    input  logic       cpha_i,
    input  logic [7:0] tx_data_i,
    output logic       busy_o,
    output logic       done_o,
    output logic [7:0] rx_data_o,
    output logic       sclk_o,
    output logic       mosi_o,
    input  logic       miso_i,
    output logic       cs_no
);
    typedef enum logic [1:0] {Idle, Run, Trail, Done} state_e;
    state_e      state;
    logic        cpha_q;
    logic [7:0]  tx_q, rx_q;
    logic [4:0]  edges;
    logic [31:0] cnt;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state     <= Idle;
            cpha_q    <= 1'b0;
            tx_q      <= '0;
            rx_q      <= '0;
            edges     <= '0;
            cnt       <= '0;
            busy_o    <= 1'b0;
            done_o    <= 1'b0;
            rx_data_o <= '0;
            sclk_o    <= 1'b0;
            mosi_o    <= 1'b0;
            cs_no     <= 1'b1;
        end else begin
            done_o <= 1'b0;
            case (state)
                Idle: if (start_i) begin
                    cpha_q <= cpha_i;
                    tx_q   <= tx_data_i;
                    mosi_o <= tx_data_i[7];
                    sclk_o <= cpol_i;
                    cs_no  <= 1'b0;
                    busy_o <= 1'b1;
                    edges  <= '0;
                    cnt    <= ClkDiv - 1;
                    state  <= Run;
                end
                Run: if (cnt != 0) cnt <= cnt - 1;
                else begin
                    cnt    <= ClkDiv - 1;
                    sclk_o <= ~sclk_o;
                    edges  <= edges + 1;
                    // Even edges lead; cpha 0 samples on them, cpha 1 on odd ones.
                    if (edges[0] == cpha_q) rx_q <= {rx_q[6:0], miso_i};
                    else if (edges != 0) begin
                        mosi_o <= tx_q[6];
                        tx_q   <= tx_q << 1;
                    end
                    if (edges == 15) state <= Trail;
                end
                Trail: if (cnt != 0) cnt <= cnt - 1;
                else begin
                    cs_no <= 1'b1;
                    state <= Done;
                end
                Done: begin
                    done_o    <= 1'b1;
                    busy_o    <= 1'b0;
                    rx_data_o <= rx_q;
                    state     <= Idle;
                end
                default: state <= Idle;
            endcase
        end
    end
endmodule
