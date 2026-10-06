// expect: OK
// note: Yosys turns the initializer into a continuous assign; Verilator and Icarus run it once at time 0 (y stays 0/x when a changes), so synthesis and simulation disagree.
module module_var_init (input logic [7:0] a, output logic [7:0] y, output logic ok);
  logic [7:0] t = a;
  assign y = t;
  assign ok = (y == a);
endmodule
