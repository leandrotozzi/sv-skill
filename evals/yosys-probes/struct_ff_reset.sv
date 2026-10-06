// expect: OK
module struct_ff_reset (input logic clk, input logic rst_n, input logic [7:0] d, output logic [7:0] y);
  typedef struct packed { logic [3:0] hi; logic [3:0] lo; } pair_t;
  pair_t r_q;
  always_ff @(posedge clk or negedge rst_n) if (!rst_n) r_q <= '0; else r_q <= d;
  assign y = r_q;
endmodule
