// expect: ERROR
// slang: OK
module case_inside_plain (input logic [3:0] a, output logic [1:0] y, output logic ok);
  always_comb begin
    case (a) inside
      1, 2: y = 2'd1;
      default: y = 2'd0;
    endcase
  end
  assign ok = (y == ((a == 1 || a == 2) ? 2'd1 : 2'd0));
endmodule
