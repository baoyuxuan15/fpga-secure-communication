`timescale 1ns/1ps
module tb_aes_enc_extra;
    reg clk = 0, rst_n = 0, start = 0;
    reg [127:0] block_in;
    wire busy, done;
    wire [127:0] block_out;
    always #10 clk = ~clk;
    aes_enc dut (.*);

    localparam P_STD = 128'h00112233445566778899aabbccddeeff;
    localparam C_STD = 128'h69c4e0d86a7b0430d8cdb78070b4c55a;
    localparam P_ON  = 128'h01000000000000000000000000000000;
    localparam C_ON  = 128'he37cd363dd7c87a09aff0e3e60e09c82;

    task automatic wait_done;
        integer cycles;
        begin
            cycles = 0;
            while (done !== 1 && cycles < 5000) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (done !== 1) $fatal(1, "timeout waiting for done");
        end
    endtask

    task automatic launch(input [127:0] p);
        begin
            @(negedge clk);
            if (busy !== 0) $fatal(1, "core not idle before start");
            block_in = p;
            start = 1;
            @(negedge clk);
            start = 0;
        end
    endtask

    task automatic check_out(input [127:0] c);
        begin
            if (block_out !== c) $fatal(1, "got %h expected %h", block_out, c);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;

        // busy ignores start and block_in changes; done is one pulse; result holds
        launch(P_STD);
        @(negedge clk);
        if (busy !== 1) $fatal(1, "busy must be 1 during computation");
        block_in = ~P_STD;
        start = 1;
        @(negedge clk);
        start = 0;
        block_in = 128'hdeadbeefdeadbeefdeadbeefdeadbeef;
        wait_done;
        check_out(C_STD);
        @(negedge clk);
        if (done !== 0) $fatal(1, "done must pulse for one clock");
        repeat (3) @(negedge clk);
        check_out(C_STD);

        // second start right after done
        launch(P_ON);
        wait_done;
        check_out(C_ON);

        // reset aborts a running task, core recovers to idle
        launch(P_STD);
        @(negedge clk);
        if (busy !== 1) $fatal(1, "expected busy before reset");
        rst_n = 0;
        repeat (2) @(negedge clk);
        if (busy !== 0 || done !== 0) $fatal(1, "reset must return core to idle");
        rst_n = 1;
        launch(P_ON);
        wait_done;
        check_out(C_ON);

        $display("PASS: aes_enc extra handshake/reset");
        $finish;
    end
endmodule