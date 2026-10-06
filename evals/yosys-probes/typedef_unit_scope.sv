// expect: OK
typedef logic [7:0] u8_t;
module typedef_unit_scope (input u8_t a, output u8_t y, output logic ok);
  assign y = a;
  assign ok = (y == a);
endmodule
