// expect: OK
module lp_case_function (input logic [1:0] i, output logic [7:0] y, output logic ok);
  function automatic logic [7:0] tbl(logic [1:0] k);
    case (k)
      2'd0: tbl = 8'h11;
      2'd1: tbl = 8'h22;
      2'd2: tbl = 8'h33;
      default: tbl = 8'h44;
    endcase
  endfunction
  assign y = tbl(i);
  assign ok = (y == ((i == 0) ? 8'h11 : (i == 1) ? 8'h22 : (i == 2) ? 8'h33 : 8'h44));
endmodule
