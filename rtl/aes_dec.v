// 5 号任务：AES-128 解密核，单分组、十轮逆密码，逐轮复用同一套组合运算。
// 数据布局取自 INTERFACE.md：第 i 字节位于 block[127-8*i -: 8]，
// 对应状态矩阵 state[row][column]，其中 row = i % 4、column = i / 4。
// 逆密码顺序：初始 AddRoundKey(10)；第 9~1 轮依次 InvShiftRows、InvSubBytes、
// AddRoundKey(round)、InvMixColumns；末轮 InvShiftRows、InvSubBytes、AddRoundKey(0)。
module aes_dec (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [127:0] block_in,
    output reg          busy,
    output reg          done,
    output reg  [127:0] block_out
);
    `include "aes_tables.vh"

    // 状态机：IDLE 等待启动；ROUND 执行第 9~1 轮；FINAL 执行末轮并同拍给出结果
    localparam [1:0] PH_IDLE  = 2'd0;
    localparam [1:0] PH_ROUND = 2'd1;
    localparam [1:0] PH_FINAL = 2'd2;

    reg [1:0]   phase;
    reg [3:0]   round;      // 当前执行到的轮号，9 递减到 1
    reg [127:0] state;      // 当前分组状态，布局与 block 相同

    // GF(2^8) 乘 2：左移一位，最高位为 1 时按 8'h1b 约减
    function [7:0] xtime;
        input [7:0] b;
        begin
            xtime = {b[6:0], 1'b0} ^ (b[7] ? 8'h1b : 8'h00);
        end
    endfunction

    // InvMixColumns 单列运算，col[31:24] 为第 0 行、col[7:0] 为第 3 行。
    // 系数换算：09 = 8^1，0B = 8^2^1，0D = 8^4^1，0E = 8^4^2。
    function [31:0] inv_mix_col;
        input [31:0] col;
        reg   [7:0]  a0, a1, a2, a3;   // 原始字节
        reg   [7:0]  b0, b1, b2, b3;   // ×2
        reg   [7:0]  c0, c1, c2, c3;   // ×4
        reg   [7:0]  d0, d1, d2, d3;   // ×8
        reg   [31:0] t;
        begin
            a0 = col[31:24];
            a1 = col[23:16];
            a2 = col[15:8];
            a3 = col[7:0];

            b0 = xtime(a0);
            c0 = xtime(b0);
            d0 = xtime(c0);
            b1 = xtime(a1);
            c1 = xtime(b1);
            d1 = xtime(c1);
            b2 = xtime(a2);
            c2 = xtime(b2);
            d2 = xtime(c2);
            b3 = xtime(a3);
            c3 = xtime(b3);
            d3 = xtime(c3);

            // 第 0 行：0E*s0 ^ 0B*s1 ^ 0D*s2 ^ 09*s3
            t[31:24] = d0 ^ c0 ^ b0 ^ d1 ^ b1 ^ a1 ^ d2 ^ c2 ^ a2 ^ d3 ^ a3;
            // 第 1 行：09*s0 ^ 0E*s1 ^ 0B*s2 ^ 0D*s3
            t[23:16] = d0 ^ a0 ^ d1 ^ c1 ^ b1 ^ d2 ^ b2 ^ a2 ^ d3 ^ c3 ^ a3;
            // 第 2 行：0D*s0 ^ 09*s1 ^ 0E*s2 ^ 0B*s3
            t[15:8]  = d0 ^ c0 ^ a0 ^ d1 ^ a1 ^ d2 ^ c2 ^ b2 ^ d3 ^ b3 ^ a3;
            // 第 3 行：0B*s0 ^ 0D*s1 ^ 09*s2 ^ 0E*s3
            t[7:0]   = d0 ^ b0 ^ a0 ^ d1 ^ c1 ^ a1 ^ d2 ^ a2 ^ d3 ^ c3 ^ b3;
            inv_mix_col = t;
        end
    endfunction

    // InvMixColumns：四列分别运算
    function [127:0] inv_mix_columns;
        input [127:0] s;
        reg   [127:0] t;
        begin
            t[127:96] = inv_mix_col(s[127:96]);
            t[95:64]  = inv_mix_col(s[95:64]);
            t[63:32]  = inv_mix_col(s[63:32]);
            t[31:0]   = inv_mix_col(s[31:0]);
            inv_mix_columns = t;
        end
    endfunction

    // InvShiftRows：第 r 行循环右移 r 字节，第 0 行不变。
    // 第 r 行第 c 列的新值来自同一行第 (c - r) mod 4 列。
    function [127:0] inv_shift_rows;
        input [127:0] s;
        reg   [127:0] t;
        begin
            t[127:120] = s[127:120];   // 行0 列0
            t[119:112] = s[23:16];     // 行1 列0 <- 行1 列3
            t[111:104] = s[47:40];     // 行2 列0 <- 行2 列2
            t[103:96]  = s[71:64];     // 行3 列0 <- 行3 列1
            t[95:88]   = s[95:88];     // 行0 列1
            t[87:80]   = s[119:112];   // 行1 列1 <- 行1 列0
            t[79:72]   = s[15:8];      // 行2 列1 <- 行2 列3
            t[71:64]   = s[39:32];     // 行3 列1 <- 行3 列2
            t[63:56]   = s[63:56];     // 行0 列2
            t[55:48]   = s[87:80];     // 行1 列2 <- 行1 列1
            t[47:40]   = s[111:104];   // 行2 列2 <- 行2 列0
            t[39:32]   = s[7:0];       // 行3 列2 <- 行3 列3
            t[31:24]   = s[31:24];     // 行0 列3
            t[23:16]   = s[55:48];     // 行1 列3 <- 行1 列2
            t[15:8]    = s[79:72];     // 行2 列3 <- 行2 列1
            t[7:0]     = s[103:96];    // 行3 列3 <- 行3 列0
            inv_shift_rows = t;
        end
    endfunction

    // InvSubBytes：逐字节查逆 S 盒
    function [127:0] inv_sub_bytes;
        input [127:0] s;
        reg   [127:0] t;
        begin
            t[127:120] = aes_inv_sbox(s[127:120]);
            t[119:112] = aes_inv_sbox(s[119:112]);
            t[111:104] = aes_inv_sbox(s[111:104]);
            t[103:96]  = aes_inv_sbox(s[103:96]);
            t[95:88]   = aes_inv_sbox(s[95:88]);
            t[87:80]   = aes_inv_sbox(s[87:80]);
            t[79:72]   = aes_inv_sbox(s[79:72]);
            t[71:64]   = aes_inv_sbox(s[71:64]);
            t[63:56]   = aes_inv_sbox(s[63:56]);
            t[55:48]   = aes_inv_sbox(s[55:48]);
            t[47:40]   = aes_inv_sbox(s[47:40]);
            t[39:32]   = aes_inv_sbox(s[39:32]);
            t[31:24]   = aes_inv_sbox(s[31:24]);
            t[23:16]   = aes_inv_sbox(s[23:16]);
            t[15:8]    = aes_inv_sbox(s[15:8]);
            t[7:0]     = aes_inv_sbox(s[7:0]);
            inv_sub_bytes = t;
        end
    endfunction

    // 第 9~1 轮：InvShiftRows → InvSubBytes → AddRoundKey(轮号) → InvMixColumns
    function [127:0] inv_round;
        input [127:0] s;
        input [3:0]   rk;
        reg   [127:0] t;
        begin
            t = inv_sub_bytes(inv_shift_rows(s));
            t = t ^ aes_round_key(rk);
            inv_round = inv_mix_columns(t);
        end
    endfunction

    // 末轮：InvShiftRows → InvSubBytes → AddRoundKey(0)，不含 InvMixColumns
    function [127:0] inv_last_round;
        input [127:0] s;
        begin
            inv_last_round = inv_sub_bytes(inv_shift_rows(s)) ^ aes_round_key(4'd0);
        end
    endfunction

    // 每拍默认清 done，使 done 只保持一个时钟周期
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase     <= PH_IDLE;
            round     <= 4'd0;
            state     <= 128'd0;
            busy      <= 1'b0;
            done      <= 1'b0;
            block_out <= 128'd0;
        end else begin
            done <= 1'b0;
            case (phase)
                PH_IDLE: begin
                    // start && !busy 的上升沿接受任务，锁存密文并先做初始轮密钥异或
                    if (start && !busy) begin
                        state <= block_in ^ aes_round_key(4'd10);
                        round <= 4'd9;
                        busy  <= 1'b1;
                        phase <= PH_ROUND;
                    end
                end
                PH_ROUND: begin
                    // 一轮一拍，忙时忽略 start 与 block_in 变化
                    state <= inv_round(state, round);
                    if (round == 4'd1) begin
                        phase <= PH_FINAL;
                    end else begin
                        round <= round - 4'd1;
                    end
                end
                PH_FINAL: begin
                    block_out <= inv_last_round(state);
                    busy      <= 1'b0;
                    done      <= 1'b1;
                    phase     <= PH_IDLE;
                end
                default: phase <= PH_IDLE;
            endcase
        end
    end
endmodule
