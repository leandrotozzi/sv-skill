// expect: ERROR
// slang: OK
module end_label_function (input logic [7:0] a, output logic [7:0] y, output logic ok);
  function automatic logic [7:0] f(logic [7:0] x);
    f = x;
  endfunction : f
  assign y = f(a);
  assign ok = (y == a);
endmodule
