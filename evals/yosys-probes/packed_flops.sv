// expect: OK
module packed_flops (input logic clk, input logic rst_n, input logic [7:0] d, output logic [7:0] y);
  logic [3:0][7:0] r_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) r_q <= '0;
    else r_q <= {r_q[2:0], d};
  end
  assign y = r_q[3];
endmodule
