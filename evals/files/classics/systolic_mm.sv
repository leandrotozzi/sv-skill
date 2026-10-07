// Output-stationary systolic matrix multiplier, C = A x B (reference for eval 133).
// Each accepted beat k enters a skew stage: row i of A is delayed i cycles and
// column j of B is delayed j cycles, so A[i][k] and B[k][j] meet in PE(i,j) at
// edge t + 1 + i + j. A values (with valid/first/last tags) move right, B values
// move down. The first beat of a matrix overwrites the accumulator. When the
// last beat leaves PE(N-1,N-1) every accumulator is final; the grid is copied
// to c_o and out_valid_o pulses 2N cycles after the last beat. in_ready_o is
// low from the last beat until that pulse.
module systolic_mm #(
    parameter int N     = 4,
    parameter int DataW = 8,
    parameter int AccW  = 32
) (
    input  logic                  clk_i,
    input  logic                  rst_ni,
    input  logic                  in_valid_i,
    output logic                  in_ready_o,
    input  logic                  in_last_i,
    input  logic [N*DataW-1:0]    a_col_i,
    input  logic [N*DataW-1:0]    b_row_i,
    output logic                  out_valid_o,
    output logic [N*N*AccW-1:0]   c_o
);
    if (N < 2 || N > 8) begin : g_bad_n
        $fatal(1, "systolic_mm: N = %0d outside 2..8", N);
    end

    function automatic logic [AccW-1:0] mac(logic [AccW-1:0] acc, logic signed [DataW-1:0] a,
                                            logic signed [DataW-1:0] b);
        logic signed [2*DataW-1:0] p;
        p = a * b;
        return acc + AccW'(p);
    endfunction

    logic fire, busy, first_q, done_q, corner_last;
    assign fire       = in_valid_i && in_ready_o;
    assign in_ready_o = !busy;

    // Skew lines: [lane][stage]; lane i is read at stage i.
    logic signed [DataW-1:0] a_sk[N][N];
    logic signed [DataW-1:0] b_sk[N][N];
    logic                    v_sk[N][N], f_sk[N][N], l_sk[N][N];

    // PE pipeline registers and accumulators.
    logic signed [DataW-1:0] pa[N][N], pb[N][N];
    logic                    pv[N][N], pf[N][N], pl[N][N];
    logic [AccW-1:0]         acc[N][N];

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            busy    <= 1'b0;
            first_q <= 1'b1;
        end else begin
            if (fire) first_q <= in_last_i;
            if (fire && in_last_i) busy <= 1'b1;
            else if (done_q) busy <= 1'b0;
        end
    end

    for (genvar i = 0; i < N; i++) begin : g_skew
        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                for (int d = 0; d < N; d++) begin
                    v_sk[i][d] <= 1'b0;
                    f_sk[i][d] <= 1'b0;
                    l_sk[i][d] <= 1'b0;
                    a_sk[i][d] <= '0;
                    b_sk[i][d] <= '0;
                end
            end else begin
                v_sk[i][0] <= fire;
                f_sk[i][0] <= first_q;
                l_sk[i][0] <= in_last_i;
                a_sk[i][0] <= a_col_i[i*DataW+:DataW];
                b_sk[i][0] <= b_row_i[i*DataW+:DataW];
                for (int d = 1; d < N; d++) begin
                    v_sk[i][d] <= v_sk[i][d-1];
                    f_sk[i][d] <= f_sk[i][d-1];
                    l_sk[i][d] <= l_sk[i][d-1];
                    a_sk[i][d] <= a_sk[i][d-1];
                    b_sk[i][d] <= b_sk[i][d-1];
                end
            end
        end
    end

    for (genvar i = 0; i < N; i++) begin : g_row
        for (genvar j = 0; j < N; j++) begin : g_col
            logic signed [DataW-1:0] ain, bin;
            logic                    vin, fin, lin;
            if (j == 0) begin : g_left
                assign ain = a_sk[i][i];
                assign vin = v_sk[i][i];
                assign fin = f_sk[i][i];
                assign lin = l_sk[i][i];
            end else begin : g_inner
                assign ain = pa[i][j-1];
                assign vin = pv[i][j-1];
                assign fin = pf[i][j-1];
                assign lin = pl[i][j-1];
            end
            if (i == 0) begin : g_top
                assign bin = b_sk[j][j];
            end else begin : g_below
                assign bin = pb[i-1][j];
            end
            if (i == N - 1 && j == N - 1) begin : g_corner
                assign corner_last = vin && lin;
            end

            always_ff @(posedge clk_i or negedge rst_ni) begin
                if (!rst_ni) begin
                    pa[i][j]  <= '0;
                    pb[i][j]  <= '0;
                    pv[i][j]  <= 1'b0;
                    pf[i][j]  <= 1'b0;
                    pl[i][j]  <= 1'b0;
                    acc[i][j] <= '0;
                end else begin
                    pa[i][j] <= ain;
                    pb[i][j] <= bin;
                    pv[i][j] <= vin;
                    pf[i][j] <= fin;
                    pl[i][j] <= lin;
                    if (vin) acc[i][j] <= mac(fin ? '0 : acc[i][j], ain, bin);
                end
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            done_q      <= 1'b0;
            out_valid_o <= 1'b0;
            c_o         <= '0;
        end else begin
            done_q      <= corner_last;
            out_valid_o <= done_q;
            if (done_q)
                for (int i = 0; i < N; i++)
                    for (int j = 0; j < N; j++) c_o[(i*N+j)*AccW+:AccW] <= acc[i][j];
        end
    end
endmodule
