// expect: OK
module gen_error_elab #(parameter int N = 4) (input logic [N-1:0] a, output logic [N-1:0] y, output logic ok);
  if (N < 1) begin : gen_chk
    $error("N must be >= 1");
  end
  assign y = a;
  assign ok = (y == a);
endmodule
