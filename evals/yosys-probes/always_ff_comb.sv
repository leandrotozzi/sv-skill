// expect: OK
module always_ff_comb (input logic clk, input logic rst_n, input logic d, output logic q);
  logic q_d;
  always_comb q_d = d;
  always_ff @(posedge clk or negedge rst_n) if (!rst_n) q <= 1'b0; else q <= q_d;
endmodule
