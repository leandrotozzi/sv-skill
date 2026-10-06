// expect: OK
module priority_case (input logic [3:0] a, output logic [1:0] y, output logic ok);
  always_comb begin
    priority casez (a)
      4'b???1: y = 2'd0;
      4'b??10: y = 2'd1;
      4'b?100: y = 2'd2;
      default: y = 2'd3;
    endcase
  end
  assign ok = (y == (a[0] ? 2'd0 : a[1] ? 2'd1 : a[2] ? 2'd2 : 2'd3));
endmodule
