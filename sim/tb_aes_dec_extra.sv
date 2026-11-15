`timescale 1ns/1ps
// 5 号 AES 解密核扩展验证：共用向量、连续任务、忙时输入变化与重复启动、复位中止及恢复。
// 运行方式见文件末尾注释；共用 sim/tb_aes.sv 的 TEST_DEC 模式仍用于标准/开灯两组向量。
module tb_aes_dec_extra;
    reg          clk = 0;
    reg          rst_n = 0;
    reg          start = 0;
    reg  [127:0] block_in = 128'd0;
    wire         busy;
    wire         done;
    wire [127:0] block_out;

    always #10 clk = ~clk;          // 50 MHz，周期 20 ns

    aes_dec dut (.*);

    // INTERFACE.md 的共用验收向量：密文送进核，期望恢复出明文
    localparam [127:0] CT_STD    = 128'h69c4e0d86a7b0430d8cdb78070b4c55a;
    localparam [127:0] PT_STD    = 128'h00112233445566778899aabbccddeeff;
    localparam [127:0] CT_ON     = 128'he37cd363dd7c87a09aff0e3e60e09c82;
    localparam [127:0] PT_ON     = 128'h01000000000000000000000000000000;
    localparam [127:0] CT_OFF    = 128'hc6a13b37878f5b826f4f8162a1c8d879;
    localparam [127:0] PT_OFF    = 128'h00000000000000000000000000000000;
    localparam [127:0] CT_ACKON  = 128'hb026dbf27fcdfabeeab01ed0cb78ac66;
    localparam [127:0] PT_ACKON  = 128'ha0010000000000000000000000000000;
    localparam [127:0] CT_ACKOFF = 128'h966aab7bda958e77dd00c494cfc001d6;
    localparam [127:0] PT_ACKOFF = 128'ha0000000000000000000000000000000;

    integer checks = 0;
    integer max_cycles = 0;
    integer cyc;

    // 一次完整任务：busy 空闲时启动，等待 done，核对结果、单拍 done 与结果保持
    task run_task(input [127:0] ct, input [127:0] pt, input integer disturb,
                  output integer cycles_out);
        integer n;
        begin
            @(negedge clk);
            if (busy !== 1'b0) $fatal(1, "core not idle before start");
            block_in = ct;
            start    = 1'b1;
            @(negedge clk);
            start    = 1'b0;
            if (busy !== 1'b1) $fatal(1, "busy must rise after accepting start");

            if (disturb != 0) begin
                // 忙时改变输入并再次拉高 start，当前任务的结果不得受影响
                block_in = 128'hdeadbeef00000000deadbeef00000000;
                start    = 1'b1;
                @(negedge clk);
                start    = 1'b0;
                block_in = 128'd0;
            end

            n = 0;
            while (done !== 1'b1 && n < 5000) begin
                @(negedge clk);
                n = n + 1;
            end
            if (done !== 1'b1) $fatal(1, "timeout waiting for done");
            if (busy !== 1'b0) $fatal(1, "busy must fall on the done cycle");
            if (block_out !== pt) $fatal(1, "block_out %h, expected %h", block_out, pt);

            @(negedge clk);
            if (done !== 1'b0) $fatal(1, "done must stay high for one clock only");
            if (block_out !== pt) $fatal(1, "block_out must hold after done");

            checks = checks + 1;
            cycles_out = n + 1;
            if (n + 1 > max_cycles) max_cycles = n + 1;
            $display("  OK   %h -> %h, %0d cycles", ct, block_out, n + 1);
        end
    endtask

    // 计算中途复位，检查中止当前任务；随后由调用方重新发起任务验证恢复
    task reset_abort;
        begin
            @(negedge clk);
            if (busy !== 1'b0) $fatal(1, "core not idle before reset test");
            block_in = CT_STD;
            start    = 1'b1;
            @(negedge clk);
            start    = 1'b0;
            repeat (4) @(negedge clk);
            if (busy !== 1'b1) $fatal(1, "busy must stay high while computing");

            rst_n = 1'b0;
            @(negedge clk);
            if (busy !== 1'b0 || done !== 1'b0) $fatal(1, "reset must abort the task");
            if (block_out !== 128'd0) $fatal(1, "reset must clear block_out");
            rst_n = 1'b1;
            @(negedge clk);

            checks = checks + 1;
            $display("  OK   reset abort: busy=0, done=0, block_out=0");
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        if (busy !== 1'b0 || done !== 1'b0) $fatal(1, "reset state must be idle");
        rst_n = 1'b1;
        @(negedge clk);

        $display("[1] 共用验收向量");
        run_task(CT_STD,    PT_STD,    0, cyc);
        run_task(CT_ON,     PT_ON,     0, cyc);
        run_task(CT_OFF,    PT_OFF,    0, cyc);
        run_task(CT_ACKON,  PT_ACKON,  0, cyc);
        run_task(CT_ACKOFF, PT_ACKOFF, 0, cyc);

        $display("[2] 连续任务，忙时改输入并重复拉 start");
        run_task(CT_STD, PT_STD, 1, cyc);
        run_task(CT_ON,  PT_ON,  1, cyc);

        $display("[3] 复位中止后重新启动");
        reset_abort;
        run_task(CT_ACKOFF, PT_ACKOFF, 0, cyc);

        $display("PASS: aes_dec extra tests (%0d checks, max %0d cycles)", checks, max_cycles);
        $finish;
    end
endmodule
// vlib work
// vlog +incdir+rtl rtl/aes_dec.v
// vlog -sv sim/tb_aes_dec_extra.sv
// vsim -c tb_aes_dec_extra -do "run -all; quit -f"
