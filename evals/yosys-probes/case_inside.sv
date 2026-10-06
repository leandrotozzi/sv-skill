// expect: ERROR
module case_inside (input logic [3:0] a, output logic [1:0] y, output logic ok);
  always_comb begin
    case (a) inside
      4'd1, 4'd2: y = 2'd1;
      [4'd8:4'd9]: y = 2'd2;
      default: y = 2'd0;
    endcase
  end
  assign ok = (y == ((a == 1 || a == 2) ? 2'd1 : (a == 8 || a == 9) ? 2'd2 : 2'd0));
endmodule
