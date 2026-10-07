// Reference for eval 135 (irq-ctrl): small PLIC-style interrupt controller.
// Sources 1..Sources on src_i[s-1]; registers as in the prompt. The claim picks
// from the state at the read edge; a source is in service from that edge on.
// After a complete the source re-pends in the following cycle (level still high,
// or an edge remembered while in service).
module irq_ctrl #(
    parameter int Sources = 8
) (
    input  logic               clk_i,
    input  logic               rst_ni,
    input  logic [Sources-1:0] src_i,
    input  logic               reg_we_i,
    input  logic               reg_re_i,
    input  logic [7:0]         reg_addr_i,
    input  logic [31:0]        reg_wdata_i,
    output logic [31:0]        reg_rdata_o,
    output logic               irq_o
);
    if (Sources < 1 || Sources > 31) begin : g_bad_sources
        $error("irq_ctrl: Sources must be 1..31, got %0d", Sources);
    end

    localparam int S = Sources;

    logic [2:0]   prio_q[S];
    logic [S-1:0] pend_q, en_q, mode_q, insvc_q, mem_q, prev_q;
    logic [2:0]   thr_q;
    logic [31:0]  rdata_q;
    logic         irq_q;

    // Highest priority pending, enabled source above the threshold; ties to the lowest id.
    logic [4:0] best_id;
    logic [2:0] best_prio;
    always_comb begin
        best_id   = '0;
        best_prio = '0;
        for (int i = 0; i < S; i++) begin
            if (pend_q[i] && en_q[i] && prio_q[i] > thr_q && (best_id == '0 || prio_q[i] > best_prio)) begin
                best_prio = prio_q[i];
                best_id   = 5'(i + 1);
            end
        end
    end

    logic         claim;
    logic [S-1:0] claim_bit, cmpl_bit, rise, set;
    always_comb begin
        claim = reg_re_i && reg_addr_i == 8'h90;
        for (int i = 0; i < S; i++) begin
            claim_bit[i] = claim && best_id == 5'(i + 1);
            cmpl_bit[i]  = reg_we_i && reg_addr_i == 8'h90 && reg_wdata_i == 32'(i + 1) && insvc_q[i];
        end
        rise = src_i & ~prev_q;
        set  = ~insvc_q & ((mode_q & rise) | (~mode_q & src_i) | mem_q);
    end

    logic [31:0] rdata_d;
    always_comb begin
        rdata_d = '0;
        case (reg_addr_i)
            8'h80: rdata_d = 32'(pend_q);
            8'h84: rdata_d = 32'(en_q);
            8'h88: rdata_d = 32'(mode_q);
            8'h8C: rdata_d = 32'(thr_q);
            8'h90: rdata_d = 32'(best_id);
            default:
                for (int i = 0; i < S; i++) if (reg_addr_i == 8'(4 * i)) rdata_d = 32'(prio_q[i]);
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            for (int i = 0; i < S; i++) prio_q[i] <= '0;
            pend_q  <= '0;
            en_q    <= '0;
            mode_q  <= '0;
            insvc_q <= '0;
            mem_q   <= '0;
            prev_q  <= '0;
            thr_q   <= '0;
            rdata_q <= '0;
            irq_q   <= 1'b0;
        end else begin
            prev_q  <= src_i;
            pend_q  <= (pend_q | set) & ~claim_bit;
            insvc_q <= (insvc_q & ~cmpl_bit) | claim_bit;
            mem_q   <= insvc_q & (mem_q | (mode_q & rise));
            irq_q   <= best_id != '0;
            if (reg_re_i) rdata_q <= rdata_d;
            if (reg_we_i) begin
                for (int i = 0; i < S; i++) if (reg_addr_i == 8'(4 * i)) prio_q[i] <= reg_wdata_i[2:0];
                case (reg_addr_i)
                    8'h84: en_q <= reg_wdata_i[S-1:0];
                    8'h88: mode_q <= reg_wdata_i[S-1:0];
                    8'h8C: thr_q <= reg_wdata_i[2:0];
                    default: ;
                endcase
            end
        end
    end

    assign reg_rdata_o = rdata_q;
    assign irq_o       = irq_q;
endmodule
