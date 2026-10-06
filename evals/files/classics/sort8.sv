// Reference pipelined sorting network (only used to validate sort8_tb).
// Batcher odd-even merge sort: 19 compare-exchange elements in 6 layers, one
// register stage per layer, latency 6.
module sort8 #(
    parameter int Width = 16
) (
    input  logic               clk_i,
    input  logic               rst_ni,
    input  logic               valid_i,
    input  logic [8*Width-1:0] data_i,
    output logic               valid_o,
    output logic [8*Width-1:0] data_o
);
    localparam int Layers = 6;
    // Comparator pairs per layer as {lo, hi} nibbles; 8'hFF marks an unused slot.
    localparam logic [7:0] Pairs [Layers][4] = '{
        '{8'h01, 8'h23, 8'h45, 8'h67},
        '{8'h02, 8'h13, 8'h46, 8'h57},
        '{8'h12, 8'h56, 8'hFF, 8'hFF},
        '{8'h04, 8'h15, 8'h26, 8'h37},
        '{8'h24, 8'h35, 8'hFF, 8'hFF},
        '{8'h12, 8'h34, 8'h56, 8'hFF}
    };

    logic [Width-1:0] key [Layers+1][8];
    logic [Layers:0]  vld;

    for (genvar k = 0; k < 8; k++) assign key[0][k] = data_i[k*Width +: Width];
    assign vld[0] = valid_i;

    for (genvar l = 0; l < Layers; l++) begin : g_layer
        logic [Width-1:0] nxt [8];
        always_comb begin
            nxt = key[l];
            for (int p = 0; p < 4; p++) begin
                if (Pairs[l][p] != 8'hFF) begin
                    automatic int a = Pairs[l][p][7:4];
                    automatic int b = Pairs[l][p][3:0];
                    if (key[l][a] > key[l][b]) begin
                        nxt[a] = key[l][b];
                        nxt[b] = key[l][a];
                    end
                end
            end
        end
        always_ff @(posedge clk_i) key[l+1] <= nxt;
        always_ff @(posedge clk_i or negedge rst_ni)
            if (!rst_ni) vld[l+1] <= 1'b0;
            else vld[l+1] <= vld[l];
    end

    for (genvar k = 0; k < 8; k++) assign data_o[k*Width +: Width] = key[Layers][k];
    assign valid_o = vld[Layers];
endmodule
