// UART transmitter: 115200, 8N1, LSB first, 50 MHz clock.
// Each bit lasts CLKS_PER_BIT clocks. Ready is high only while idle.
module uart_tx (
    input wire clk, rst_n, tx_valid,
    input wire [7:0] tx_data,
    output reg tx_ready,
    output reg uart_txd
);
    localparam CLKS_PER_BIT = 9'd434;

    localparam S_IDLE  = 3'd0;  // line high, ready to accept a byte
    localparam S_START = 3'd1;  // send start bit (low)
    localparam S_DATA  = 3'd2;  // send 8 data bits, bit 0 first
    localparam S_STOP  = 3'd3;  // send stop bit (high)

    reg [2:0] state;
    reg [8:0] cnt;        // 0 .. CLKS_PER_BIT-1 inside the current bit
    reg [2:0] bit_idx;    // data bit 0 .. 7
    reg [7:0] tx_data_q;   // byte latched on the handshake edge

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            cnt       <= 9'd0;
            bit_idx   <= 3'd0;
            tx_data_q <= 8'd0;
            tx_ready  <= 1'b1;
            uart_txd  <= 1'b1;
        end else begin
            case (state)
                S_IDLE: begin
                    tx_ready <= 1'b1;
                    uart_txd <= 1'b1;
                    cnt      <= 9'd0;
                    bit_idx  <= 3'd0;
                    // Accept a byte on the valid && ready edge.
                    if (tx_valid == 1'b1) begin
                        tx_data_q <= tx_data;
                        state     <= S_START;
                        tx_ready  <= 1'b0;
                        cnt       <= 9'd0;
                    end
                end

                S_START: begin
                    uart_txd <= 1'b0;   // start bit
                    tx_ready <= 1'b0;
                    if (cnt == CLKS_PER_BIT - 9'd1) begin
                        state   <= S_DATA;
                        cnt     <= 9'd0;
                        bit_idx <= 3'd0;
                    end else begin
                        cnt <= cnt + 9'd1;
                    end
                end

                S_DATA: begin
                    uart_txd <= tx_data_q[bit_idx];  // LSB first
                    tx_ready <= 1'b0;
                    if (cnt == CLKS_PER_BIT - 9'd1) begin
                        cnt <= 9'd0;
                        if (bit_idx == 3'd7) begin
                            state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                        end
                    end else begin
                        cnt <= cnt + 9'd1;
                    end
                end

                S_STOP: begin
                    uart_txd <= 1'b1;   // stop bit, a full 434 clocks
                    // S_STOP starts counting on the entry clock itself, so it
                    // needs one extra count compared with the other bits.
                    if (cnt == CLKS_PER_BIT) begin
                        // Whole stop bit sent: only now report ready again.
                        state    <= S_IDLE;
                        tx_ready <= 1'b1;
                        cnt      <= 9'd0;
                    end else begin
                        cnt <= cnt + 9'd1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
