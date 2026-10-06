// Reference SECDED (72,64) encoder (only used to validate secded_tb.sv).
// Extended Hamming: data bit i gets the i-th 7-bit column that is not a power
// of two; check bits 0..6 are the unit columns, check bit 7 is overall parity.
module secded_enc (
    input  logic [63:0] data_i,
    output logic [71:0] code_o
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
        logic [6:0] c;
        c = '0;
        for (int i = 0; i < 64; i++) if (data_i[i]) c ^= col(i);
        code_o = {^{c, data_i}, c, data_i};
    end
endmodule
