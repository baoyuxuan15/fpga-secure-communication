module aes_enc (
    input wire clk, rst_n, start,
    input wire [127:0] block_in,
    output wire busy, done,
    output wire [127:0] block_out
);
    `include "aes_tables.vh"

    localparam S_IDLE  = 1'b0;
    localparam S_ROUND = 1'b1;

    reg         fsm_r;
    reg [127:0] state_r;
    reg [127:0] out_r;
    reg [3:0]   round_r;
    reg         busy_r;
    reg         done_r;

    assign busy      = busy_r;
    assign done      = done_r;
    assign block_out = out_r;

    function [7:0] xtime;
        input [7:0] b;
        begin
            xtime = b[7] ? ((b << 1) ^ 8'h1b) : (b << 1);
        end
    endfunction

    function [7:0] mul3;
        input [7:0] b;
        begin
            mul3 = xtime(b) ^ b;
        end
    endfunction

    // byte i = block[127-8*i -: 8] = state[row=i%4][col=i/4]
    function [127:0] round_fn;
        input [127:0] s;
        input [3:0] rnd;
        reg [7:0] sb [0:15];
        reg [7:0] sr [0:15];
        reg [7:0] mc [0:15];
        reg [127:0] rk;
        reg [127:0] res;
        integer i, c, r;
        begin
            for (i = 0; i < 16; i = i + 1)
                sb[i] = aes_sbox(s[127-8*i -: 8]);
            // ShiftRows: row r rotates left by r
            for (c = 0; c < 4; c = c + 1)
                for (r = 0; r < 4; r = r + 1)
                    sr[4*c+r] = sb[4*((c+r)%4)+r];
            if (rnd < 4'd10) begin
                for (c = 0; c < 4; c = c + 1) begin
                    mc[4*c+0] = xtime(sr[4*c+0]) ^ mul3(sr[4*c+1]) ^ sr[4*c+2] ^ sr[4*c+3];
                    mc[4*c+1] = sr[4*c+0] ^ xtime(sr[4*c+1]) ^ mul3(sr[4*c+2]) ^ sr[4*c+3];
                    mc[4*c+2] = sr[4*c+0] ^ sr[4*c+1] ^ xtime(sr[4*c+2]) ^ mul3(sr[4*c+3]);
                    mc[4*c+3] = mul3(sr[4*c+0]) ^ sr[4*c+1] ^ sr[4*c+2] ^ xtime(sr[4*c+3]);
                end
            end else begin
                // final round has no MixColumns
                for (i = 0; i < 16; i = i + 1)
                    mc[i] = sr[i];
            end
            rk = aes_round_key(rnd);
            for (i = 0; i < 16; i = i + 1)
                res[127-8*i -: 8] = mc[i] ^ rk[127-8*i -: 8];
            round_fn = res;
        end
    endfunction

    wire [127:0] next_state = round_fn(state_r, round_r);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fsm_r   <= S_IDLE;
            state_r <= 128'd0;
            out_r   <= 128'd0;
            round_r <= 4'd0;
            busy_r  <= 1'b0;
            done_r  <= 1'b0;
        end else begin
            case (fsm_r)
                S_IDLE: begin
                    done_r <= 1'b0;
                    if (start) begin
                        state_r <= block_in ^ aes_round_key(4'd0);
                        round_r <= 4'd1;
                        busy_r  <= 1'b1;
                        fsm_r   <= S_ROUND;
                    end
                end
                S_ROUND: begin
                    state_r <= next_state;
                    if (round_r == 4'd10) begin
                        out_r  <= next_state;
                        busy_r <= 1'b0;
                        done_r <= 1'b1;
                        fsm_r  <= S_IDLE;
                    end else begin
                        round_r <= round_r + 4'd1;
                    end
                end
                default: begin
                    fsm_r  <= S_IDLE;
                    busy_r <= 1'b0;
                    done_r <= 1'b0;
                end
            endcase
        end
    end
endmodule