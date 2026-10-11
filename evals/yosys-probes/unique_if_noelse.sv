// expect: WRONG
// slang: OK
// note: unique if without else: Yosys drops the preceding default, simulation keeps it.
module unique_if_noelse (input logic [1:0] a, output logic [3:0] y, output logic ok);
  always_comb begin
    y = 4'd0;
    unique if (a == 2'd0) y = 4'd1;
    else if (a == 2'd1) y = 4'd2;
  end
  assign ok = (y == ((a == 0) ? 4'd1 : (a == 1) ? 4'd2 : 4'd0));
endmodule
