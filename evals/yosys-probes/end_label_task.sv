// expect: ERROR
// slang: OK
module end_label_task (input logic [7:0] a, output logic [7:0] y, output logic ok);
  task automatic t(input logic [7:0] x, output logic [7:0] o);
    o = x;
  endtask : t
  always_comb t(a, y);
  assign ok = (y == a);
endmodule
