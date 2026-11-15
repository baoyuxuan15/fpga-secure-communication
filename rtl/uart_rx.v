// UART receiver: 115200, 8N1, LSB first, 50 MHz clock.
// Each bit lasts CLKS_PER_BIT clocks; data is sampled at the bit center.
module uart_rx (
    input wire clk, rst_n, uart_rxd,
    output reg rx_valid,
    output reg [7:0] rx_data
);
    localparam CLKS_PER_BIT = 9'd434;
    localparam BIT_CENTER   = 9'd216;  // 217th clock of a bit, its center

    localparam S_IDLE       = 3'd0;    // line high, wait for start edge
    localparam S_START      = 3'd1;    // confirm start bit at its center
    localparam S_DATA       = 3'd2;    // sample 8 data bits
    localparam S_STOP       = 3'd3;    // check stop bit at its center
    localparam S_WAIT_HIGH  = 3'd4;    // framing error: wait for line high

    // Two-stage synchronizer for the asynchronous RX line. Idle is high.
    reg rx_meta, rx_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= uart_rxd;
            rx_sync <= rx_meta;
        end
    end

    reg [2:0]  state;
    reg [8:0]  cnt;        // 0 .. CLKS_PER_BIT-1 inside the current bit
    reg [2:0]  bit_idx;    // data bit 0 .. 7, LSB arrives first
    reg [7:0]  rx_shift;   // bits shifted in, bit 0 lands in rx_shift[0]

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            cnt      <= 9'd0;
            bit_idx  <= 3'd0;
            rx_shift <= 8'd0;
            rx_data  <= 8'd0;
            rx_valid <= 1'b0;
        end else begin
            // rx_valid is a one-clock pulse; clear it unless set this cycle.
            rx_valid <= 1'b0;
            case (state)
                S_IDLE: begin
                    cnt     <= 9'd0;
                    bit_idx <= 3'd0;
                    if (rx_sync == 1'b0) begin
                        // Possible start bit; confirm it at its center.
                        state <= S_START;
                        cnt   <= 9'd0;
                    end
                end

                S_START: begin
                    if (cnt == BIT_CENTER && rx_sync == 1'b1) begin
                        // Glitch: back to idle and wait for a new edge.
                        state <= S_IDLE;
                        cnt   <= 9'd0;
                    end else if (cnt == CLKS_PER_BIT - 9'd1) begin
                        // Start bit confirmed after a full 434 clocks.
                        state   <= S_DATA;
                        cnt     <= 9'd0;
                        bit_idx <= 3'd0;
                    end else begin
                        cnt <= cnt + 9'd1;
                    end
                end

                S_DATA: begin
                    if (cnt == BIT_CENTER) begin
                        // Sample this bit at its center; LSB first.
                        rx_shift <= {rx_sync, rx_shift[7:1]};
                        cnt      <= cnt + 9'd1;
                    end else if (cnt == CLKS_PER_BIT - 9'd1) begin
                        // End of this bit: the next one starts at cnt = 0.
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
                    if (cnt == BIT_CENTER) begin
                        // Decide the byte here, at the stop-bit center, so a
                        // back-to-back start bit is not mistaken for a bad
                        // stop bit at the end of the bit.
                        if (rx_sync == 1'b1) begin
                            rx_data  <= rx_shift;
                            rx_valid <= 1'b1;
                            state    <= S_IDLE;
                        end else begin
                            // Framing error: drop the byte, wait for idle high.
                            state <= S_WAIT_HIGH;
                        end
                        cnt <= 9'd0;
                    end else begin
                        cnt <= cnt + 9'd1;
                    end
                end

                S_WAIT_HIGH: begin
                    cnt <= 9'd0;
                    if (rx_sync == 1'b1) begin
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
