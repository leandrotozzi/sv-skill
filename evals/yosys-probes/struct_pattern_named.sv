// expect: ERROR
// slang: OK
module struct_pattern_named (input logic [3:0] a, input logic [3:0] b, output logic [7:0] y, output logic ok);
  typedef struct packed { logic [3:0] hi; logic [3:0] lo; } pair_t;
  pair_t s;
  assign s = '{hi: a, lo: b};
  assign y = s;
  assign ok = (y == {a, b});
endmodule
