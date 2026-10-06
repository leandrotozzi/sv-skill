// Reference leading-zero counter (only used to validate lzc_tb).
module lzc #(
    parameter int Width = 16
) (
    input  logic [Width-1:0]         data_i,
    output logic [$clog2(Width):0]   cnt_o,
    output logic                     zero_o
);
    always_comb begin
        cnt_o = ($clog2(Width) + 1)'(Width);
        for (int i = 0; i < Width; i++) if (data_i[i]) cnt_o = ($clog2(Width) + 1)'(Width - 1 - i);
    end
    assign zero_o = data_i == '0;
endmodule
