// expect: ERROR
module string_param #(parameter string Mode = "fast") (output logic y, output logic ok);
  assign y = (Mode == "fast");
  assign ok = (y == 1'b1);
endmodule
