`timescale 1ns/1ps
// Real debounce + application; only the public armed command is driven here.
module tb_alarm_ctrl;
    reg clk = 0, rst_n = 0, armed = 0;
    reg [3:0] key_n = 4'hf;
    wire [3:0] key_pressed, held;
    wire alarm_active, muted, selftest_active, alarm_light, muted_light, test_light, beep;
    wire [15:0] count_bcd;
    reg direct_mode = 0;
    reg [3:0] direct_keys = 0;
    wire [3:0] app_keys = direct_mode ? direct_keys : key_pressed;
    integer press_count = 0, sound_edges = 0;
    always #10 clk = !clk;
    genvar k;
    generate for (k=0;k<4;k=k+1) begin: filters
        key_debounce #(.DEBOUNCE_CYCLES(4)) filter (
            .clk(clk), .rst_n(rst_n), .key_n(key_n[k]), .pressed(key_pressed[k]), .held(held[k]));
    end endgenerate
    alarm_ctrl #(.BLINK_CYCLES(12), .CHIRP_CYCLES(10), .SELFTEST_CYCLES(30), .TONE_HALF_CYCLES(2)) dut (
        .clk(clk), .rst_n(rst_n), .armed(armed), .key_pressed(app_keys),
        .trigger_held(held[0]), .alarm_active(alarm_active), .muted(muted),
        .selftest_active(selftest_active), .count_bcd(count_bcd), .alarm_light(alarm_light),
        .muted_light(muted_light), .test_light(test_light), .beep(beep));
    always @(posedge clk) if (key_pressed[0]) press_count = press_count + 1;
    always @(negedge beep) if (rst_n) sound_edges = sound_edges + 1;
    task tick(input integer n);
        repeat(n) @(negedge clk);
    endtask
    task press(input integer i);
        key_n[i]=0; tick(10); key_n[i]=1; tick(10);
    endtask
    task event_pulse(input [3:0] keys);
        direct_keys=keys; tick(1); direct_keys=0; tick(1);
    endtask
    integer i, edges_before;
    initial begin
        tick(2); rst_n=1; tick(2);
        if (alarm_active || muted || count_bcd || beep !== 1) $fatal(1,"reset");
        // Short low and release bounce must not count as presses.
        key_n[0]=0; tick(2); key_n[0]=1; tick(8);
        if (press_count != 0) $fatal(1,"short glitch became press");
        press(0);
        if (alarm_active || count_bcd || press_count != 1) $fatal(1,"disarmed input");
        armed=1; tick(2); edges_before=sound_edges; tick(6);
        if (sound_edges == edges_before) $fatal(1,"arm chirp missing");
        tick(15); if (beep !== 1) $fatal(1,"chirp did not finish");
        // Bouncy press, long hold and bouncy release each produce one event.
        key_n[0]=0; tick(1); key_n[0]=1; tick(1); key_n[0]=0; tick(40);
        if (!alarm_active || muted || count_bcd !== 16'h0001) $fatal(1,"held trigger");
        key_n[0]=1; tick(1); key_n[0]=0; tick(1); key_n[0]=1; tick(10);
        if (press_count != 2 || count_bcd !== 16'h0001) $fatal(1,"release bounce");
        press(1); tick(2);
        if (!alarm_active || !muted || !muted_light || beep !== 1) $fatal(1,"mute cleared event");
        edges_before=sound_edges; tick(50);
        if (sound_edges != edges_before) $fatal(1,"muted sound");
        press(0);
        if (muted || count_bcd !== 16'h0002) $fatal(1,"new trigger did not unmute");
        press(3); if (count_bcd !== 16'h0002) $fatal(1,"armed clear allowed");
        press(2); if (selftest_active) $fatal(1,"armed selftest allowed");
        armed=0; tick(1);
        if (alarm_active || muted || alarm_light || beep !== 1 || count_bcd !== 16'h0002)
            $fatal(1,"disarm should clear alarm but keep count");
        press(3); if (count_bcd !== 16'd0) $fatal(1,"disarmed clear");
        key_n[2]=0; tick(10);
        if (!selftest_active || !alarm_light || !test_light || !muted_light) $fatal(1,"selftest");
        key_n[2]=1; tick(40);
        if (selftest_active || count_bcd || beep !== 1) $fatal(1,"selftest completion");
        key_n[2]=0; tick(10);
        if (!selftest_active) $fatal(1,"selftest restart");
        armed=1; tick(2);
        if (selftest_active || test_light) $fatal(1,"arm must cancel selftest");
        armed=0; key_n[2]=1; tick(15);
        // A simulated open door held across arming must alarm immediately.
        key_n[0]=0; tick(10); armed=1; tick(2);
        if (!alarm_active || count_bcd !== 16'h0001) $fatal(1,"held input at arm");
        key_n[0]=1; tick(10);
        // Direct pulses test priorities and the full decimal rollover range.
        direct_mode=1;
        event_pulse(4'b0011);
        if (muted || count_bcd !== 16'h0002) $fatal(1,"trigger must beat mute");
        armed=0; direct_keys=4'b1111; tick(1); direct_keys=0; tick(1);
        if (alarm_active || muted || count_bcd || selftest_active) $fatal(1,"disarm priority");
        armed=1; tick(2);
        for (i=1; i<=10005; i=i+1) begin
            event_pulse(4'b0001);
            if (i==10 && count_bcd !== 16'h0010) $fatal(1,"decimal 9->10");
            if (i==100 && count_bcd !== 16'h0100) $fatal(1,"decimal 99->100");
            if (i==1000 && count_bcd !== 16'h1000) $fatal(1,"decimal 999->1000");
        end
        if (count_bcd !== 16'h9999) $fatal(1,"count must saturate");
        rst_n=0; #1;
        if (alarm_active || muted || count_bcd || beep !== 1) $fatal(1,"reset during alarm");
        $display("PASS: alarm debounce, priorities, sound, selftest, BCD saturation");
        $finish;
    end
    initial begin #2000000; $fatal(1,"watchdog"); end
endmodule
