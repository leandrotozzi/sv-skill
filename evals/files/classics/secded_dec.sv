// Reference SECDED (72,64) decoder (only used to validate secded_tb.sv).
// Same H as secded_enc: corrects any single flipped bit, flags any double.
module secded_dec (
    input  logic [71:0] code_i,
    output logic [63:0] data_o,
    output logic        single_err_o,
    output logic        double_err_o
);
    function automatic logic [6:0] col(int i);
        int n = 0;
        for (int v = 3; v < 128; v++) begin
            if ((v & (v - 1)) == 0) continue;
            if (n == i) return 7'(v);
            n++;
        end
        return '0;
    endfunction

    always_comb begin
        logic [6:0] s;
        logic       p;
        s = code_i[70:64];
        for (int i = 0; i < 64; i++) if (code_i[i]) s ^= col(i);
        p = ^code_i;
        data_o = code_i[63:0];
        for (int i = 0; i < 64; i++) if (p && s == col(i)) data_o[i] = ~data_o[i];
        single_err_o = p;
        double_err_o = !p && s != 0;
    end
endmodule
