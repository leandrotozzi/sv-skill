// expect: OK
module enum_basic (input logic clk, input logic rst_n, output logic [1:0] y);
  typedef enum logic [1:0] {Idle, Run, Done} st_e;
  st_e st_q, st_d;
  always_comb begin
    st_d = st_q;
    unique case (st_q)
      Idle: st_d = Run;
      Run: st_d = Done;
      default: st_d = Idle;
    endcase
  end
  always_ff @(posedge clk or negedge rst_n) if (!rst_n) st_q <= Idle; else st_q <= st_d;
  assign y = st_q;
endmodule
