// expect: OK
module string_param_untyped #(parameter Mode = "fast") (output logic y, output logic ok);
  assign y = (Mode == "fast");
  assign ok = (y == 1'b1);
endmodule
