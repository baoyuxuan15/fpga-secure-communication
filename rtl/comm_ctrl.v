module comm_ctrl (
    input wire clk, rst_n, rx_valid, tx_ready,
    input wire [7:0] rx_data,
    output wire tx_valid,
    output reg led_on,
    output wire [7:0] tx_data,
    output wire dec_start, enc_start,
    output reg [127:0] dec_input, enc_input,
    input wire dec_busy, dec_done, enc_busy, enc_done,
    input wire [127:0] dec_output, enc_output
);
    localparam [2:0] RECEIVE = 3'd0, START_DEC = 3'd1, WAIT_DEC = 3'd2,
                     START_ENC = 3'd3, WAIT_ENC = 3'd4, SEND = 3'd5;
    localparam [127:0] CMD_ON = {8'h01, 120'd0}, CMD_OFF = 128'd0;

    reg [2:0] state;
    reg [3:0] byte_index;
    reg [127:0] reply_shift;

    assign dec_start = (state == START_DEC) && !dec_busy;
    assign enc_start = (state == START_ENC) && !enc_busy;
    assign tx_valid = (state == SEND);
    assign tx_data = reply_shift[127:120];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= RECEIVE;
            byte_index  <= 4'd0;
            dec_input   <= 128'd0;
            enc_input   <= 128'd0;
            reply_shift <= 128'd0;
            led_on      <= 1'b0;
        end else begin
            case (state)
                RECEIVE: if (rx_valid) begin
                    // After byte 15 is sampled, the first byte is at [127:120].
                    dec_input <= {dec_input[119:0], rx_data};
                    byte_index <= byte_index + 4'd1;
                    if (byte_index == 4'd15)
                        state <= START_DEC;
                end
                START_DEC: if (dec_start)
                    state <= WAIT_DEC;
                WAIT_DEC: if (dec_done) begin
                    // Validate the entire block. Success reports the new LED state.
                    if (dec_output == CMD_ON) begin
                        led_on <= 1'b1;
                        enc_input <= {8'hA0, 8'h01, 112'd0};
                    end else if (dec_output == CMD_OFF) begin
                        led_on <= 1'b0;
                        enc_input <= {8'hA0, 8'h00, 112'd0};
                    end else begin
                        enc_input <= {8'hE0, 7'd0, led_on, 112'd0};
                    end
                    state <= START_ENC;
                end
                START_ENC: if (enc_start)
                    state <= WAIT_ENC;
                WAIT_ENC: if (enc_done) begin
                    reply_shift <= enc_output;
                    state <= SEND;
                end
                SEND: if (tx_ready) begin
                    reply_shift <= {reply_shift[119:0], 8'd0};
                    // The 4-bit index wraps to zero on each frame's last byte.
                    byte_index <= byte_index + 4'd1;
                    if (byte_index == 4'd15)
                        state <= RECEIVE;
                end
                default: begin
                    state <= RECEIVE;
                    byte_index <= 4'd0;
                end
            endcase
        end
    end
endmodule
