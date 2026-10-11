// expect: ERROR
// slang: OK
module struct_pattern_default (output logic [7:0] y, output logic ok);
  typedef struct packed { logic [3:0] hi; logic [3:0] lo; } pair_t;
  pair_t s;
  assign s = '{default: '0};
  assign y = s;
  assign ok = (y == 8'd0);
endmodule
