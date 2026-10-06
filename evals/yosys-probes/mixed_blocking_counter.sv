// expect: OK
module mixed_blocking_counter (input logic clk, input logic rst_n, output logic [3:0] y);
  logic [3:0] c_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) c_q <= '0;
    else c_q <= c_q + 4'd1;
  end
  assign y = c_q;
endmodule
