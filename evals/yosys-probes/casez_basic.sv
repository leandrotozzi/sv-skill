// expect: OK
module casez_basic (input logic [3:0] a, output logic [1:0] y, output logic ok);
  always_comb begin
    casez (a)
      4'b1???: y = 2'd3;
      4'b01??: y = 2'd2;
      4'b001?: y = 2'd1;
      default: y = 2'd0;
    endcase
  end
  assign ok = (y == (a[3] ? 2'd3 : a[2] ? 2'd2 : a[1] ? 2'd1 : 2'd0));
endmodule
