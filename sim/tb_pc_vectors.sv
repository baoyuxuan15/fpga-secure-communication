`timescale 1ns/1ps
// 6 号跨端向量：按电脑端发送顺序把 on/off 请求密文送入真实的 aes_dec，
// 等待 done 后按串口字节顺序逐字节核对解密明文。
// 分组首字节位于 block_in[127:120]，末字节位于 [7:0]；这与 pc/demo.py 写出的
// 16 字节顺序一致。两个密文来自 python pc/reference.py 的 request(led_on) 输出。
module tb_pc_vectors;
    reg          clk = 0;
    reg          rst_n = 0;
    reg          start = 0;
    reg  [127:0] block_in = 128'd0;
    wire         busy;
    wire         done;
    wire [127:0] block_out;

    always #10 clk = ~clk;          // 50 MHz，周期 20 ns

    aes_dec dut (.*);

    // 开灯：电脑发送 e3 7c d3 63 ... 9c 82，板上应解出 01 后接 15 字节零
    localparam [127:0] CT_ON  = 128'he37cd363dd7c87a09aff0e3e60e09c82;
    localparam [127:0] PT_ON  = 128'h01000000000000000000000000000000;
    // 关灯：电脑发送 c6 a1 3b 37 ... c8 d8 79，板上应解出 16 字节零
    localparam [127:0] CT_OFF = 128'hc6a13b37878f5b826f4f8162a1c8d879;
    localparam [127:0] PT_OFF = 128'h00000000000000000000000000000000;

    integer checks = 0;
    integer max_cycles = 0;

    // 启动一次真实解密，等 done 后按字节下标 0..15 核对；下标 0 即首字节。
    task run_vector(input [127:0] ct, input [127:0] pt);
        integer i;
        integer n;
        reg [7:0] got;
        reg [7:0] exp;
        begin
            @(negedge clk);
            if (busy !== 1'b0)
                $fatal(1, "aes_dec busy before start");

            // 在上升沿前建立 block_in 和 start，DUT 在该沿锁存分组
            block_in = ct;
            start    = 1'b1;
            @(negedge clk);
            start    = 1'b0;
            if (busy !== 1'b1)
                $fatal(1, "busy did not rise after start");

            n = 0;
            while (done !== 1'b1 && n < 5000) begin
                @(negedge clk);
                n = n + 1;
            end
            if (done !== 1'b1)
                $fatal(1, "timeout waiting for done");
            if (busy !== 1'b0)
                $fatal(1, "busy must be low on the done cycle");

            // 逐字节核对，既验证明文内容，也验证 [127:120] 起始的字节顺序
            for (i = 0; i < 16; i = i + 1) begin
                got = block_out[127 - 8*i -: 8];
                exp = pt[127 - 8*i -: 8];
                if (got !== exp)
                    $fatal(1, "byte %0d mismatch: got %02h expected %02h", i, got, exp);
            end

            $display("  PASS ct=%h -> pt=%h (16 bytes)", ct, block_out);
            checks = checks + 16;
            if ((n + 1) > max_cycles)
                max_cycles = n + 1;

            // done 只允许保持一拍；结果保持到下一次任务
            @(negedge clk);
            if (done !== 1'b0)
                $fatal(1, "done must clear on the next clock");
            if (block_out !== pt)
                $fatal(1, "block_out changed after done");
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        if (busy !== 1'b0 || done !== 1'b0)
            $fatal(1, "reset state must be idle");
        rst_n = 1'b1;
        @(negedge clk);

        $display("[1] PC on request: first byte in [127:120]");
        run_vector(CT_ON, PT_ON);

        $display("[2] PC off request: first byte in [127:120]");
        run_vector(CT_OFF, PT_OFF);

        if (checks != 32)
            $fatal(1, "expected 32 byte checks, got %0d", checks);
        $display("PASS: tb_pc_vectors on/off byte order (%0d bytes, max %0d cycles)",
                 checks, max_cycles);
        $finish;
    end
endmodule
// 从仓库根目录运行：
// vlib work
// vlog +incdir+rtl rtl/aes_dec.v
// vlog -sv sim/tb_pc_vectors.sv
// vsim -c tb_pc_vectors -do "run -all; quit -f"
