// Reference byte-wide IEEE 802.3 CRC-32 (reflected, poly 0xEDB88320 reversed form).
module crc32 (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        init_i,
    input  logic        valid_i,
    input  logic [7:0]  data_i,
    output logic [31:0] crc_o
);
    logic [31:0] crc_q, crc_next;

    always_comb begin
        crc_next = crc_q ^ {24'h0, data_i};
        for (int b = 0; b < 8; b++) begin
            crc_next = crc_next[0] ? ((crc_next >> 1) ^ 32'hEDB88320) : (crc_next >> 1);
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)      crc_q <= 32'hFFFFFFFF;
        else if (init_i)  crc_q <= 32'hFFFFFFFF;
        else if (valid_i) crc_q <= crc_next;
    end

    assign crc_o = crc_q ^ 32'hFFFFFFFF;
endmodule
