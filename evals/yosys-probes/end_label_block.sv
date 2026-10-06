// expect: OK
module end_label_block (input logic [7:0] a, output logic [7:0] y, output logic ok);
  always_comb begin : blk
    y = a;
  end : blk
  for (genvar g = 0; g < 1; g++) begin : gen_x
  end : gen_x
  assign ok = (y == a);
endmodule : end_label_block
