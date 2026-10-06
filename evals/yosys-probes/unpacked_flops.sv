// expect: WARN
module unpacked_flops (input logic clk, input logic [7:0] d, output logic [7:0] y);
  logic [7:0] r_q [4];
  always_ff @(posedge clk) begin
    r_q[0] <= d;
    for (int i = 1; i < 4; i++) r_q[i] <= r_q[i-1];
  end
  assign y = r_q[3];
endmodule
