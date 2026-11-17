// Application layer. The existing communication core owns the armed bit.
module alarm_ctrl #(
    parameter integer BLINK_CYCLES = 12500000, // 250 ms half-period
    parameter integer CHIRP_CYCLES = 5000000,  // 100 ms arm confirmation
    parameter integer SELFTEST_CYCLES = 50000000,
    parameter integer TONE_HALF_CYCLES = 12500 // 2 kHz passive buzzer
) (
    input wire clk, rst_n, armed,
    input wire [3:0] key_pressed,
    input wire trigger_held,
    output reg alarm_active, muted,
    output wire selftest_active,
    output reg [15:0] count_bcd,
    output wire alarm_light, muted_light, test_light,
    output wire beep
);
    reg armed_prev, blink_phase, tone;
    reg [31:0] blink_count, chirp_count, test_count, tone_count;
    wire trigger_event = armed &&
        (key_pressed[0] || (!armed_prev && trigger_held));
    wire sound_enable = rst_n && (alarm_active ?
        (armed && !muted && blink_phase) :
        ((armed && chirp_count != 32'd0) || selftest_active));

    assign selftest_active = !armed && (test_count != 32'd0);
    assign alarm_light = rst_n && ((armed && alarm_active && blink_phase) || selftest_active);
    assign muted_light = rst_n && ((armed && alarm_active && muted) || selftest_active);
    assign test_light = rst_n && selftest_active;
    // Board PNP driver: idle high, square wave only during an audible interval.
    assign beep = sound_enable ? !tone : 1'b1;

    function [15:0] increment_bcd;
        input [15:0] value;
        begin
            increment_bcd = value;
            if (value != 16'h9999) begin
                if (value[3:0] != 4'd9)
                    increment_bcd[3:0] = value[3:0] + 4'd1;
                else begin
                    increment_bcd[3:0] = 4'd0;
                    if (value[7:4] != 4'd9)
                        increment_bcd[7:4] = value[7:4] + 4'd1;
                    else begin
                        increment_bcd[7:4] = 4'd0;
                        if (value[11:8] != 4'd9)
                            increment_bcd[11:8] = value[11:8] + 4'd1;
                        else begin
                            increment_bcd[11:8] = 4'd0;
                            increment_bcd[15:12] = value[15:12] + 4'd1;
                        end
                    end
                end
            end
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            armed_prev <= 1'b0;
            alarm_active <= 1'b0;
            muted <= 1'b0;
            count_bcd <= 16'd0;
            chirp_count <= 32'd0;
            test_count <= 32'd0;
        end else begin
            armed_prev <= armed;
            if (chirp_count != 32'd0)
                chirp_count <= chirp_count - 32'd1;
            if (test_count != 32'd0)
                test_count <= test_count - 32'd1;

            // Disarm dominates trigger/mute; only disarmed KEY4 may clear count.
            if (!armed) begin
                alarm_active <= 1'b0;
                muted <= 1'b0;
                chirp_count <= 32'd0;
                if (armed_prev)
                    test_count <= 32'd0;
                else if (key_pressed[2])
                    test_count <= SELFTEST_CYCLES;
                if (key_pressed[3])
                    count_bcd <= 16'd0;
            end else begin
                test_count <= 32'd0;
                if (!armed_prev)
                    chirp_count <= CHIRP_CYCLES;
                if (trigger_event) begin
                    alarm_active <= 1'b1;
                    muted <= 1'b0;
                    chirp_count <= 32'd0;
                    count_bcd <= increment_bcd(count_bcd);
                end else if (key_pressed[1] && alarm_active)
                    muted <= 1'b1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            blink_count <= 32'd0;
            blink_phase <= 1'b1;
        end else if (!armed || !alarm_active || trigger_event) begin
            blink_count <= 32'd0;
            blink_phase <= 1'b1;
        end else if (blink_count == BLINK_CYCLES - 1) begin
            blink_count <= 32'd0;
            blink_phase <= !blink_phase;
        end else
            blink_count <= blink_count + 32'd1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tone_count <= 32'd0;
            tone <= 1'b0;
        end else if (!sound_enable) begin
            tone_count <= 32'd0;
            tone <= 1'b0;
        end else if (tone_count == TONE_HALF_CYCLES - 1) begin
            tone_count <= 32'd0;
            tone <= !tone;
        end else
            tone_count <= tone_count + 32'd1;
    end
endmodule
