// Alarm revision wraps the public ports of the unchanged secure_comm top.
module alarm_top #(
    parameter integer DEBOUNCE_CYCLES = 1000000,
    parameter integer BLINK_CYCLES = 12500000,
    parameter integer CHIRP_CYCLES = 5000000,
    parameter integer SELFTEST_CYCLES = 50000000,
    parameter integer TONE_HALF_CYCLES = 12500,
    parameter integer DISPLAY_HOLD_CYCLES = 50000,
    parameter integer DISPLAY_SERIAL_DIV = 25
) (
    input wire clk, rst_n, uart_rxd,
    input wire [3:0] key_n,
    output wire uart_txd, led_n,
    output wire alarm_led_n, muted_led_n, test_led_n, beep,
    output wire shcp, stcp, ds, oe
);
    wire core_led_n;
    wire armed = !core_led_n;
    wire [3:0] key_pressed, key_held;
    wire alarm_active, muted, selftest_active;
    wire alarm_light, muted_light, test_light;
    wire [15:0] count_bcd;

    top secure_core (.clk(clk), .rst_n(rst_n), .uart_rxd(uart_rxd),
                     .uart_txd(uart_txd), .led_n(core_led_n));
    assign led_n = core_led_n; // D6 always means armed, including during selftest.
    assign alarm_led_n = !alarm_light;
    assign muted_led_n = !muted_light;
    assign test_led_n = !test_light;

    genvar k;
    generate for (k = 0; k < 4; k = k + 1) begin: keys
        key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) filter (
            .clk(clk), .rst_n(rst_n), .key_n(key_n[k]),
            .pressed(key_pressed[k]), .held(key_held[k]));
    end endgenerate

    alarm_ctrl #(.BLINK_CYCLES(BLINK_CYCLES), .CHIRP_CYCLES(CHIRP_CYCLES),
                 .SELFTEST_CYCLES(SELFTEST_CYCLES), .TONE_HALF_CYCLES(TONE_HALF_CYCLES)) app (
        .clk(clk), .rst_n(rst_n), .armed(armed), .key_pressed(key_pressed),
        .trigger_held(key_held[0]), .alarm_active(alarm_active), .muted(muted),
        .selftest_active(selftest_active), .count_bcd(count_bcd),
        .alarm_light(alarm_light), .muted_light(muted_light), .test_light(test_light), .beep(beep));

    alarm_display #(.HOLD_CYCLES(DISPLAY_HOLD_CYCLES), .SERIAL_DIV(DISPLAY_SERIAL_DIV)) display (
        .clk(clk), .rst_n(rst_n), .count_bcd(count_bcd), .selftest_active(selftest_active),
        .shcp(shcp), .stcp(stcp), .ds(ds), .oe(oe));
endmodule
