// expect: ERROR
// slang: OK
module array_pattern_default (input logic clk, input logic rst_n, input logic [7:0] d, output logic [7:0] y);
  logic [7:0] r_q [2];
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) r_q <= '{default: '0};
    else begin r_q[0] <= d; r_q[1] <= r_q[0]; end
  end
  assign y = r_q[1];
endmodule
