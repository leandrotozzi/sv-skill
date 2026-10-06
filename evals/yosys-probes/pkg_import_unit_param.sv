// expect: OK
package pk;
  typedef enum logic [1:0] {A, B, C} st_e;
  localparam int W = 8;
endpackage
import pk::*;
module pkg_import_unit_param (output logic [7:0] y, output logic ok);
  assign y = 8'(W) + 8'(B);
  assign ok = (y == 8'd9);
endmodule
