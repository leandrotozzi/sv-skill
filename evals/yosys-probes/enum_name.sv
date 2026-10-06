// expect: ERROR
module enum_name (input logic [1:0] a, output logic y);
  typedef enum logic [1:0] {S0, S1, S2, S3} st_e;
  st_e s;
  assign s = st_e'(a);
  always_comb begin
    y = 1'b0;
    if (s.name() == "S1") y = 1'b1;
  end
endmodule
