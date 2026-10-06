// expect: OK
module unique0_case (input logic [1:0] a, output logic [3:0] y, output logic ok);
  always_comb begin
    y = 4'd0;
    unique0 case (a)
      2'd0: y = 4'd1;
      2'd1: y = 4'd2;
    endcase
  end
  assign ok = (y == ((a == 0) ? 4'd1 : (a == 1) ? 4'd2 : 4'd0));
endmodule
