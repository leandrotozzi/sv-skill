// expect: OK
package lpk;
  localparam int K = 3;
endpackage : lpk
module end_label_package (output logic [7:0] y, output logic ok);
  assign y = 8'(lpk::K);
  assign ok = (y == 8'd3);
endmodule
