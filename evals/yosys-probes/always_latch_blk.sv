// expect: OK
module always_latch_blk (input logic en, input logic d, output logic q);
  always_latch if (en) q = d;
endmodule
