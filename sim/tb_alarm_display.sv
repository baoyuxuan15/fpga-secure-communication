`timescale 1ns/1ps
// Observe only 595 pins, reconstructing exactly what real shift registers see.
module tb_alarm_display;
    reg clk=0, rst_n=0, selftest_active=0;
    reg [15:0] count_bcd=16'h1234;
    wire shcp, stcp, ds, oe;
    reg [13:0] received=0;
    integer bits=0, frames=0, expected_digit=0;
    reg [7:0] expected_segments;
    reg [13:0] expected_word;
    reg check_frames=1;
    always #10 clk=!clk;
    alarm_display #(.HOLD_CYCLES(4), .SERIAL_DIV(2)) dut (.*);
    always @(posedge shcp) if (rst_n) begin
        if (oe !== 1) $fatal(1,"display not blanked during shift");
        received[bits]=ds;
        bits=bits+1;
    end
    always @(posedge stcp) if (rst_n) begin
        if (bits != 14) $fatal(1,"latch with %0d bits",bits);
        if (check_frames) begin
            if (selftest_active) expected_segments=8'h80;
            else case(expected_digit)
                0: expected_segments=8'h99; // rightmost digit: 4
                1: expected_segments=8'hb0;
                2: expected_segments=8'ha4;
                3: expected_segments=8'hf9;
                default: expected_segments=8'hff;
            endcase
            expected_word={expected_segments[0],expected_segments[1],expected_segments[2],
                expected_segments[3],expected_segments[4],expected_segments[5],
                expected_segments[6],expected_segments[7],(6'b000001 << expected_digit)};
            if (received !== expected_word) $fatal(1,"digit %0d got %h expected %h",expected_digit,received,expected_word);
        end
        bits=0;
        frames=frames+1;
        expected_digit=(expected_digit==5)?0:expected_digit+1;
    end
    initial begin
        #25; rst_n=1;
        wait(frames==12); @(negedge clk);
        // Reset establishes a fresh scan and prevents changing a frame mid-shift.
        rst_n=0; #1;
        if (oe !== 1 || shcp || stcp) $fatal(1,"reset must blank outputs");
        bits=0; expected_digit=0; selftest_active=1;
        @(negedge clk); rst_n=1;
        wait(frames==18); @(negedge clk);
        $display("PASS: display 14-bit wire order, six digits, blanking, selftest, reset");
        $finish;
    end
    initial begin #100000; $fatal(1,"watchdog"); end
endmodule
