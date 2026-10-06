// expect: OK
module unique_case (input logic [1:0] a, output logic [3:0] y, output logic ok);
  always_comb begin
    unique case (a)
      2'd0: y = 4'd1;
      2'd1: y = 4'd2;
      2'd2: y = 4'd4;
      default: y = 4'd8;
    endcase
  end
  assign ok = (y == (4'd1 << a));
endmodule
