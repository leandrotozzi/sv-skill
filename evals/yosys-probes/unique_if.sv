// expect: OK
module unique_if (input logic [1:0] a, output logic [1:0] y, output logic ok);
  always_comb begin
    unique if (a == 2'd0) y = 2'd3;
    else if (a == 2'd1) y = 2'd2;
    else y = 2'd0;
  end
  assign ok = (y == ((a == 0) ? 2'd3 : (a == 1) ? 2'd2 : 2'd0));
endmodule
