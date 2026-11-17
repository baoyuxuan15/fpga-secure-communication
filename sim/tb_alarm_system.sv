`timescale 1ns/1ps
// Full real RTL: serial pins -> UART -> AES -> controller -> alarm -> serial reply.
module tb_alarm_system;
    reg clk=0, rst_n=0, uart_rxd=1;
    reg [3:0] key_n=4'hf;
    wire uart_txd, led_n, alarm_led_n, muted_led_n, test_led_n, beep, shcp, stcp, ds, oe;
    wire [7:0] monitor_data;
    wire monitor_valid;
    reg [127:0] received=0;
    integer reply_bytes=0, sound_edges=0;
    localparam [127:0] ARM=128'he37cd363dd7c87a09aff0e3e60e09c82;
    localparam [127:0] DISARM=128'hc6a13b37878f5b826f4f8162a1c8d879;
    localparam [127:0] ARM_REPLY=128'hb026dbf27fcdfabeeab01ed0cb78ac66;
    localparam [127:0] DISARM_REPLY=128'h966aab7bda958e77dd00c494cfc001d6;
    alarm_top #(.DEBOUNCE_CYCLES(4), .BLINK_CYCLES(1000), .CHIRP_CYCLES(100),
        .SELFTEST_CYCLES(200), .TONE_HALF_CYCLES(3),
        .DISPLAY_HOLD_CYCLES(4), .DISPLAY_SERIAL_DIV(2)) dut (.*);
    uart_rx monitor (.clk(clk), .rst_n(rst_n), .uart_rxd(uart_txd),
                     .rx_data(monitor_data), .rx_valid(monitor_valid));
    always #10 clk=!clk;
    always @(posedge clk) if (rst_n && monitor_valid) begin
        received={received[119:0],monitor_data};
        reply_bytes=reply_bytes+1;
    end
    always @(negedge beep) if (rst_n) sound_edges=sound_edges+1;
    task ticks(input integer n); repeat(n) @(negedge clk); endtask
    task send_byte(input [7:0] value);
        integer b;
        uart_rxd=0; ticks(434);
        for(b=0;b<8;b=b+1) begin uart_rxd=value[b]; ticks(434); end
        uart_rxd=1; ticks(434);
    endtask
    task exchange(input [127:0] request, input [127:0] expected);
        integer b, before_bytes, timeout_cycles;
        before_bytes=reply_bytes;
        for(b=0;b<16;b=b+1) send_byte(request[127-8*b -: 8]);
        timeout_cycles=0;
        while(reply_bytes < before_bytes+16 && timeout_cycles<100000) begin
            ticks(1); timeout_cycles=timeout_cycles+1;
        end
        if(reply_bytes != before_bytes+16 || received !== expected)
            $fatal(1,"encrypted exchange got %h, bytes=%0d",received,reply_bytes-before_bytes);
        ticks(500); // Finish the monitor's last stop bit before another exchange.
    endtask
    task press(input integer i);
        key_n[i]=0; ticks(10); key_n[i]=1; ticks(10);
    endtask
    integer before_edges, i;
    initial begin
        ticks(3); rst_n=1; ticks(5);
        press(0);
        if (!led_n || !alarm_led_n || beep !== 1) $fatal(1,"disarmed trigger");
        exchange(ARM,ARM_REPLY);
        if (led_n !== 0) $fatal(1,"encrypted arm");
        before_edges=sound_edges; press(0); ticks(100);
        if (alarm_led_n !== 0 || sound_edges==before_edges) $fatal(1,"alarm outputs");
        press(1); before_edges=sound_edges; ticks(2200);
        if (muted_led_n !== 0 || beep !== 1 || sound_edges!=before_edges) $fatal(1,"mute outputs");
        // A repeated arm must preserve a silenced existing alarm.
        exchange(ARM,ARM_REPLY);
        if (muted_led_n !== 0) $fatal(1,"repeat arm changed alarm");
        exchange(DISARM,DISARM_REPLY);
        if (!led_n || !muted_led_n || !alarm_led_n || beep !== 1) $fatal(1,"encrypted disarm");
        key_n[2]=0; ticks(10);
        if (test_led_n !== 0 || led_n !== 1) $fatal(1,"selftest changes armed LED");
        key_n[2]=1; ticks(250);
        if (test_led_n !== 1 || beep !== 1) $fatal(1,"selftest did not end");
        // Invalid encrypted command must leave the armed state intact.
        exchange(ARM,ARM_REPLY);
        exchange(128'h7fe6e7fa6b07ff190da174c7d7c9f362,128'ha47db3cbac8e8bf5c007ff13f2df1a09);
        if (led_n !== 0) $fatal(1,"invalid command disarmed");
        exchange(DISARM,DISARM_REPLY);
        for (i=0;i<8;i=i+1) send_byte(ARM[127-8*i -: 8]);
        ticks(1000); if (led_n !== 1) $fatal(1,"half frame armed");
        rst_n=0; ticks(3); rst_n=1; ticks(5);
        exchange(ARM,ARM_REPLY);
        press(0); rst_n=0; #1;
        if (!led_n || !alarm_led_n || !muted_led_n || beep !== 1 || oe !== 1)
            $fatal(1,"reset during alarm");
        $display("PASS: full alarm system, real UART/AES, encrypted replies, invalid/half-frame/reset");
        $finish;
    end
    initial begin #30000000; $fatal(1,"watchdog"); end
endmodule
