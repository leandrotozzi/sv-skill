// expect: OK
module generate_no_keyword #(parameter int N = 4, parameter bit Inv = 1'b1) (input logic [N-1:0] a, output logic [N-1:0] y, output logic ok);
  for (genvar i = 0; i < N; i++) begin : gen_bit
    if (Inv) begin : gen_inv
      assign y[i] = ~a[i];
    end else begin : gen_buf
      assign y[i] = a[i];
    end
  end
  assign ok = (y == ~a);
endmodule
