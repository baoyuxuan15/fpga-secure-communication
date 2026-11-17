// Six-digit common-anode display through the board's two 74HC595s.
// Scan right to left: four decimal count digits, then two blanks. Selftest: 888888.
module alarm_display #(
    parameter integer HOLD_CYCLES = 50000, // about 1 ms per digit
    parameter integer SERIAL_DIV = 25    // 1 MHz SHCP at 50 MHz; >= 1
) (
    input wire clk, rst_n,
    input wire [15:0] count_bcd,
    input wire selftest_active,
    output reg shcp, stcp, ds, oe
);
    localparam [2:0] LOAD = 3'd0, SETUP = 3'd1, HIGH = 3'd2,
                     LOW = 3'd3, LATCH = 3'd4, HOLD = 3'd5;
    reg [2:0] state, digit_index;
    reg [3:0] bit_index;
    reg [13:0] shift_data;
    reg [31:0] serial_count, hold_count;
    reg [3:0] numeral;
    reg [7:0] segments;
    wire [5:0] select_digit = 6'b000001 << digit_index;

    always @* begin
        numeral = 4'hf;
        case (digit_index)
            3'd0: numeral = count_bcd[3:0];
            3'd1: numeral = count_bcd[7:4];
            3'd2: numeral = count_bcd[11:8];
            3'd3: numeral = count_bcd[15:12];
            default: numeral = 4'hf;
        endcase
        if (selftest_active)
            numeral = 4'd8;
        case (numeral)
            4'd0: segments = 8'hc0;
            4'd1: segments = 8'hf9;
            4'd2: segments = 8'ha4;
            4'd3: segments = 8'hb0;
            4'd4: segments = 8'h99;
            4'd5: segments = 8'h92;
            4'd6: segments = 8'h82;
            4'd7: segments = 8'hf8;
            4'd8: segments = 8'h80;
            4'd9: segments = 8'h90;
            default: segments = 8'hff;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= LOAD;
            digit_index <= 3'd0;
            bit_index <= 4'd0;
            shift_data <= 14'd0;
            serial_count <= 32'd0;
            hold_count <= 32'd0;
            shcp <= 1'b0;
            stcp <= 1'b0;
            ds <= 1'b0;
            oe <= 1'b1;
        end else begin
            case (state)
                LOAD: begin
                    oe <= 1'b1; // Blank before changing the selected digit.
                    stcp <= 1'b0;
                    shcp <= 1'b0;
                    // Official board order: sel[0..5], seg[7..0], LSB first.
                    shift_data <= {segments[0], segments[1], segments[2], segments[3],
                                   segments[4], segments[5], segments[6], segments[7], select_digit};
                    bit_index <= 4'd0;
                    serial_count <= 32'd0;
                    state <= SETUP;
                end
                SETUP: begin
                    ds <= shift_data[0];
                    state <= HIGH;
                end
                HIGH: begin
                    if (serial_count == SERIAL_DIV - 1) begin
                        shcp <= 1'b1;
                        serial_count <= 32'd0;
                        state <= LOW;
                    end else
                        serial_count <= serial_count + 32'd1;
                end
                LOW: begin
                    if (serial_count == SERIAL_DIV - 1) begin
                        shcp <= 1'b0;
                        serial_count <= 32'd0;
                        if (bit_index == 4'd13)
                            state <= LATCH;
                        else begin
                            bit_index <= bit_index + 4'd1;
                            shift_data <= {1'b0, shift_data[13:1]};
                            state <= SETUP;
                        end
                    end else
                        serial_count <= serial_count + 32'd1;
                end
                LATCH: begin
                    stcp <= 1'b1;
                    hold_count <= 32'd0;
                    state <= HOLD;
                end
                HOLD: begin
                    stcp <= 1'b0;
                    oe <= 1'b0; // Enable only after the complete word was latched.
                    if (hold_count == HOLD_CYCLES - 1) begin
                        hold_count <= 32'd0;
                        digit_index <= (digit_index == 3'd5) ? 3'd0 : digit_index + 3'd1;
                        state <= LOAD;
                    end else
                        hold_count <= hold_count + 32'd1;
                end
                default: begin
                    oe <= 1'b1;
                    shcp <= 1'b0;
                    stcp <= 1'b0;
                    digit_index <= 3'd0;
                    state <= LOAD;
                end
            endcase
        end
    end
endmodule
