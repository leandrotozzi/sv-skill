// expect: OK
module generate_keyword #(parameter int N = 4) (input logic [N-1:0] a, output logic [N-1:0] y, output logic ok);
  genvar i;
  generate
    for (i = 0; i < N; i = i + 1) begin : gen_bit
      assign y[i] = ~a[i];
    end
  endgenerate
  assign ok = (y == ~a);
endmodule
