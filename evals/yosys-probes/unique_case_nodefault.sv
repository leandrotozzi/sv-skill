// expect: WRONG
// note: Yosys treats unique as full_case, so the y = 0 default before the case is dropped for a = 2, 3; simulation keeps 0 (plus a violation report).
module unique_case_nodefault (input logic [1:0] a, output logic [3:0] y, output logic ok);
  always_comb begin
    y = 4'd0;
    unique case (a)
      2'd0: y = 4'd1;
      2'd1: y = 4'd2;
    endcase
  end
  assign ok = (y == ((a == 0) ? 4'd1 : (a == 1) ? 4'd2 : 4'd0));
endmodule
