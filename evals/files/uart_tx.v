// uart_tx.v -- legacy transmitter, 8N1, one start bit and one stop bit.
module uart_tx (clk, rst_n, start, data, tx, busy);
  parameter CLKS_PER_BIT = 4;
  input clk;
  input rst_n;
  input start;
  input [7:0] data;
  output tx;
  output busy;
  reg tx;
  reg busy;
  reg [3:0] bit_idx;
  reg [15:0] clk_cnt;
  reg [9:0] shreg;

  always @(posedge clk or negedge rst_n)
    if (!rst_n) begin
      tx <= 1'b1; busy <= 1'b0; bit_idx <= 0; clk_cnt <= 0; shreg <= 10'h3ff;
    end else if (!busy) begin
      if (start) begin
        shreg <= {1'b1, data, 1'b0};
        busy <= 1'b1;
        clk_cnt <= 0;
        bit_idx <= 0;
      end
    end else begin
      if (clk_cnt == CLKS_PER_BIT-1) begin
        clk_cnt <= 0;
        tx <= shreg[0];
        shreg <= {1'b1, shreg[9:1]};
        if (bit_idx == 9) busy <= 1'b0;
        bit_idx <= bit_idx + 1;
      end else
        clk_cnt <= clk_cnt + 1;
    end
endmodule
