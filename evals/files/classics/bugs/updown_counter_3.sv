// Reference for eval 102: up/down counter, load has priority over enable.
// Planted bug 3: counts up without enable.
module updown_counter #(
    parameter int Width = 8
) (
    input  logic             clk_i,
    input  logic             rst_ni,
    input  logic             en_i,
    input  logic             load_i,
    input  logic [Width-1:0] load_val_i,
    input  logic             up_i,
    output logic [Width-1:0] count_o
);
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) count_o <= '0;
        else if (load_i) count_o <= load_val_i;
        else if (up_i) count_o <= count_o + 1'b1;  // wraps modulo 2**Width
        else if (en_i) count_o <= count_o - 1'b1;
    end
endmodule
