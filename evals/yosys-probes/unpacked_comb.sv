// expect: WARN
// slang: OK
module unpacked_comb (input logic [7:0] a, output logic [7:0] y, output logic ok);
  logic [7:0] s [4];
  always_comb begin
    s[0] = a;
    for (int i = 1; i < 4; i++) s[i] = s[i-1] + 8'd1;
  end
  assign y = s[3];
  assign ok = (y == a + 8'd3);
endmodule
