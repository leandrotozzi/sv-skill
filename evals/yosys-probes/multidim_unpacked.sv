// expect: WARN
// slang: OK
module multidim_unpacked (input logic [7:0] a, input logic i, input logic j, output logic [7:0] y, output logic ok);
  logic [7:0] m [2][2];
  always_comb begin
    m[0][0] = a; m[0][1] = ~a; m[1][0] = a + 8'd1; m[1][1] = a - 8'd1;
  end
  assign y = m[i][j];
  assign ok = (y == (i ? (j ? a - 8'd1 : a + 8'd1) : (j ? ~a : a)));
endmodule
