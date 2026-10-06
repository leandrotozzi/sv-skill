// expect: ERROR
interface lbl_if;
  logic [7:0] data;
endinterface : lbl_if
module endinterface_label (input logic [7:0] a, output logic [7:0] y, output logic ok);
  lbl_if b ();
  assign b.data = a;
  assign y = b.data;
  assign ok = (y == a);
endmodule
