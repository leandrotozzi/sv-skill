// expect: OK
module ram_infer (input logic clk, input logic we, input logic [3:0] wa, input logic [3:0] ra,
                  input logic [7:0] wd, output logic [7:0] rd);
  logic [7:0] mem [16];
  always_ff @(posedge clk) begin
    if (we) mem[wa] <= wd;
    rd <= mem[ra];
  end
endmodule
