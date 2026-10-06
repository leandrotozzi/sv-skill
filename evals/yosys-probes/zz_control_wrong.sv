// expect: WRONG
// note: control probe; must report WRONG, proving the sat check catches a wrong netlist.
module zz_control_wrong (input logic [7:0] a, output logic [7:0] y, output logic ok);
  assign y = a;
  assign ok = (y == a + 8'd1);
endmodule
