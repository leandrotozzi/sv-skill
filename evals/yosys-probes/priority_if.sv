// expect: OK
module priority_if (input logic [1:0] a, output logic [1:0] y, output logic ok);
  always_comb begin
    priority if (a[1]) y = 2'd2;
    else if (a[0]) y = 2'd1;
    else y = 2'd0;
  end
  assign ok = (y == (a[1] ? 2'd2 : a[0] ? 2'd1 : 2'd0));
endmodule
