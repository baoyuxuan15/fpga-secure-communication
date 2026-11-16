`timescale 1ns/1ps
// Exercise the real controller. The bench supplies UART bytes/ready and
// models the two AES cores at their public busy/start/done interfaces.
module tb_comm_ctrl;
    reg clk = 0, rst_n = 1;
    reg rx_valid = 0, tx_ready = 0;
    reg [7:0] rx_data = 0;
    reg dec_busy = 0, dec_done = 0, enc_busy = 0, enc_done = 0;
    reg [127:0] dec_output = 0, enc_output = 0;
    wire tx_valid, led_on, dec_start, enc_start;
    wire [7:0] tx_data;
    wire [127:0] dec_input, enc_input;
    comm_ctrl dut (.*);
    always #10 clk = ~clk;

    localparam [127:0] REQUEST = 128'h0021436587a9cbed1032547698badcfe;
    localparam [127:0] RESPONSE = 128'hfe01dc23ba459867768954ab32cd10ef;
    localparam [127:0] CMD_ON = {8'h01, 120'd0};
    integer dec_count = 0, enc_count = 0, tx_count = 0;

    always @(posedge clk) begin
        if (rst_n) begin
            if (dec_start) begin
                if (dec_busy) $fatal(1, "decrypt start while busy");
                dec_count = dec_count + 1;
            end
            if (enc_start) begin
                if (enc_busy) $fatal(1, "encrypt start while busy");
                enc_count = enc_count + 1;
            end
            if (tx_valid && tx_ready) tx_count = tx_count + 1;
        end
    end

    task automatic reset_controller;
        rst_n = 0;
        rx_valid = 0;
        tx_ready = 0;
        dec_busy = 0;
        dec_done = 0;
        enc_busy = 0;
        enc_done = 0;
        #1;
        if ({dec_start, enc_start, tx_valid, led_on, tx_data, dec_input, enc_input} !== '0)
            $fatal(1, "reset did not clear controller outputs");
        @(negedge clk);
        rst_n = 1;
    endtask

    // Each driver changes inputs at falling edges, away from the sampling edge.
    task automatic send_byte(input reg [7:0] data);
        rx_valid = 1;
        rx_data = data;
        @(negedge clk);
        rx_valid = 0;
    endtask

    task automatic exchange(input reg [127:0] plain, input reg [7:0] status,
                            input bit expected_led, input integer delay_cycles);
        reg [127:0] expected_reply;
        reg old_led;
        integer d0, e0, t0, i;
        d0 = dec_count;
        e0 = enc_count;
        t0 = tx_count;
        old_led = led_on;
        expected_reply = {status, 7'd0, expected_led, 112'd0};
        for (i = 0; i < 15; i = i + 1)
            send_byte(REQUEST[127-8*i -: 8]);
        repeat (4) @(negedge clk);
        if (dec_start !== 0 || dec_count != d0)
            $fatal(1, "decrypt started on an incomplete frame");

        dec_busy = 1;
        enc_busy = 1;
        send_byte(REQUEST[7:0]);
        // Unsolicited RX bytes must be discarded until the last TX handshake.
        rx_valid = 1;
        rx_data = 8'hff;
        repeat (3) @(negedge clk);
        dec_busy = 0;
        wait (dec_start === 1);
        @(posedge clk);
        if (dec_input !== REQUEST) $fatal(1, "incorrect RX order: %h", dec_input);
        @(negedge clk);
        dec_busy = 1;
        repeat (delay_cycles) @(negedge clk);
        if (led_on !== old_led || enc_count != e0 || tx_valid !== 0)
            $fatal(1, "acted before decrypt done");
        dec_output = plain;
        dec_busy = 0;
        dec_done = 1;
        @(negedge clk);
        dec_done = 0;
        dec_output = ~plain;
        repeat (2) @(negedge clk);
        enc_busy = 0;
        wait (enc_start === 1);
        @(posedge clk);
        if (enc_input !== expected_reply || led_on !== expected_led)
            $fatal(1, "command %h: expected %h got %h LED=%b", plain,
                   expected_reply, enc_input, led_on);
        @(negedge clk);
        enc_busy = 1;
        repeat (delay_cycles + 3) @(negedge clk);
        if (tx_valid !== 0) $fatal(1, "TX started before encrypt done");
        enc_output = RESPONSE;
        enc_busy = 0;
        enc_done = 1;
        @(negedge clk);
        enc_done = 0;
        enc_output = ~RESPONSE;

        wait (tx_valid === 1);
        for (i = 0; i < 16; i = i + 1) begin
            repeat (i % 4) begin
                @(negedge clk);
                if (tx_valid !== 1 || tx_data !== RESPONSE[127-8*i -: 8])
                    $fatal(1, "stalled TX byte %0d changed", i);
            end
            tx_ready = 1;
            @(posedge clk);
            if (tx_valid !== 1 || tx_data !== RESPONSE[127-8*i -: 8])
                $fatal(1, "incorrect TX handshake at byte %0d", i);
            @(negedge clk);
            tx_ready = 0;
        end
        rx_valid = 0;
        if (tx_valid !== 0 || tx_count != t0 + 16 ||
            dec_count != d0 + 1 || enc_count != e0 + 1)
            $fatal(1, "unexpected handshake counts or extra TX byte");
    endtask

    initial begin
        @(negedge clk);
        reset_controller();
        repeat (8) send_byte(8'h55);
        reset_controller();
        exchange(CMD_ON, 8'ha0, 1, 1);
        exchange(CMD_ON, 8'ha0, 1, 6);
        exchange(CMD_ON | 128'd1, 8'he0, 1, 3);
        exchange(128'd0, 8'ha0, 0, 7);
        exchange(128'd1, 8'he0, 0, 2);
        exchange({8'h02, 120'd0}, 8'he0, 0, 5);
        $display("PASS: half-frame reset, 6 commands, %0d decrypt starts, %0d encrypt starts, %0d TX handshakes",
                 dec_count, enc_count, tx_count);
        $finish;
    end

    initial begin
        repeat (2000) @(posedge clk);
        $fatal(1, "timeout waiting for a protocol handshake");
    end
endmodule
