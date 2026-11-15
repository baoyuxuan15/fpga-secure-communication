`timescale 1ns/1ps
// Independent UART testbench for role 2.
//   A. Loopback TX -> RX: 00, 55, AA, FF, check data and receive count.
//   B. Direct serial stimulus into RX: verify LSB-first bit order.
//   C. Monitor TX line directly: check start/stop bits and 434-clock bit width.
//   D. Hold tx_valid while busy: current byte finishes before the next is taken.
//   E. Reset mid-byte: a fresh complete byte is received after recovery.
module tb_uart;
    localparam integer CLKS_PER_BIT = 434;

    reg clk = 0, rst_n = 0;
    reg        tx_valid;
    reg  [7:0] tx_data;
    wire       tx_ready, uart_txd;
    wire       rx_valid;
    wire [7:0] rx_data;

    // Loopback mux: either connect TX to RX, or drive RX from a serial task.
    reg loopback;
    reg rx_drive;
    wire uart_rxd;
    assign uart_rxd = loopback ? uart_txd : rx_drive;

    integer rx_count = 0;
    // Latch the latest received byte so a one-cycle rx_valid pulse cannot be
    // missed by the polling stimulus.
    reg [7:0] rx_buf;
    reg       rx_flag;

    always #10 clk = ~clk;

    uart_rx receiver (
        .clk(clk), .rst_n(rst_n), .uart_rxd(uart_rxd),
        .rx_valid(rx_valid), .rx_data(rx_data)
    );
    uart_tx sender (
        .clk(clk), .rst_n(rst_n), .tx_data(tx_data),
        .tx_valid(tx_valid), .tx_ready(tx_ready), .uart_txd(uart_txd)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_buf  <= 8'd0;
            rx_flag <= 1'b0;
        end else if (rx_valid === 1'b1) begin
            rx_buf  <= rx_data;
            rx_flag <= 1'b1;
        end
    end

    always @(posedge clk) begin
        if (rx_valid === 1'b1) rx_count = rx_count + 1;
    end

    // Send one byte through the TX->RX loopback and compare the received byte.
    task send_loopback;
        input [7:0] tx_byte;
        begin
            @(negedge clk);
            while (tx_ready !== 1'b1) @(negedge clk);
            tx_data  = tx_byte;
            tx_valid = 1'b1;
            @(negedge clk);
            // Handshake: ready drops once the byte is latched. Release valid
            // right away; the busy transmitter ignores it and finishes the
            // current byte, then rests idle without re-sending.
            while (tx_ready === 1'b1) @(negedge clk);
            tx_valid = 1'b0;
            // Wait for the latched received byte.
            while (rx_flag !== 1'b1) @(negedge clk);
            if (rx_buf !== tx_byte)
                $fatal(1, "loopback: got %h expected %h", rx_buf, tx_byte);
            rx_flag = 1'b0;
            @(negedge clk);
        end
    endtask

    // Drive one 8N1 byte straight onto the RX line, LSB first.
    task drive_rx_byte;
        input [7:0] tx_byte;
        integer i;
        begin
            // Start bit (low)
            rx_drive = 1'b0;
            repeat (CLKS_PER_BIT) @(negedge clk);
            // Data bits, bit 0 first
            for (i = 0; i < 8; i = i + 1) begin
                rx_drive = tx_byte[i];
                repeat (CLKS_PER_BIT) @(negedge clk);
            end
            // Stop bit (high)
            rx_drive = 1'b1;
            repeat (CLKS_PER_BIT) @(negedge clk);
        end
    endtask

    // Drive a byte whose stop bit is held low (framing error), then release
    // the line high. The receiver must drop the byte and wait for idle.
    task drive_rx_bad_stop;
        input [7:0] tx_byte;
        integer i;
        begin
            rx_drive = 1'b0;
            repeat (CLKS_PER_BIT) @(negedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx_drive = tx_byte[i];
                repeat (CLKS_PER_BIT) @(negedge clk);
            end
            rx_drive = 1'b0;  // bad stop bit (should be high)
            repeat (CLKS_PER_BIT) @(negedge clk);
            rx_drive = 1'b1;  // recover the line to idle high
            repeat (CLKS_PER_BIT) @(negedge clk);
        end
    endtask

    // Wait for one latched RX byte and compare against the expected value.
    task check_rx;
        input [7:0] expected;
        begin
            while (rx_flag !== 1'b1) @(negedge clk);
            if (rx_buf !== expected)
                $fatal(1, "rx stimulus: got %h expected %h", rx_buf, expected);
            rx_flag = 1'b0;
            @(negedge clk);
        end
    endtask

    initial begin
        tx_valid = 1'b0;
        tx_data  = 8'd0;
        loopback = 1'b1;
        rx_drive = 1'b1;

        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        // A. Loopback four known bytes.
        $display("stage A t=%0d", $time);
        send_loopback(8'h00);
        send_loopback(8'h55);
        send_loopback(8'hAA);
        send_loopback(8'hFF);
        if (rx_count !== 4)
            $fatal(1, "loopback: expected 4 rx pulses, got %0d", rx_count);

        // B. Independent RX bit-order stimulus (TX disconnected from RX).
        $display("stage B t=%0d", $time);
        loopback = 1'b0;
        drive_rx_byte(8'hA5); check_rx(8'hA5);
        drive_rx_byte(8'h00); check_rx(8'h00);
        drive_rx_byte(8'hFF); check_rx(8'hFF);
        // Framing error: bad stop bit must be dropped, no rx_valid pulse.
        drive_rx_bad_stop(8'hA5);
        @(negedge clk);
        if (rx_count !== 7)
            $fatal(1, "framing error: expected 7 pulses, got %0d", rx_count);
        // Line recovered: a fresh byte is received normally.
        drive_rx_byte(8'h12); check_rx(8'h12);
        if (rx_count !== 8)
            $fatal(1, "rx stimulus: expected 8 rx pulses, got %0d", rx_count);

        // C. Monitor the TX line directly: start bit, LSB-first data, stop bit.
        $display("stage C t=%0d", $time);
        begin
            integer i;
            reg [7:0] probe;
            probe = 8'h5A;  // 0101 1010, bit 0 = 0
            @(negedge clk);
            while (tx_ready !== 1'b1) @(negedge clk);
            tx_data  = probe;
            tx_valid = 1'b1;
            @(negedge clk);
            while (tx_ready === 1'b1) @(negedge clk);
            tx_valid = 1'b0;

            // Wait for the start edge, then check a full low start bit.
            while (uart_txd === 1'b1) @(negedge clk);
            repeat (CLKS_PER_BIT) begin
                if (uart_txd !== 1'b0) $fatal(1, "tx start bit must be low");
                @(negedge clk);
            end
            // Data bits, bit 0 first.
            for (i = 0; i < 8; i = i + 1) begin
                repeat (CLKS_PER_BIT) begin
                    if (uart_txd !== probe[i])
                        $fatal(1, "tx bit %0d: line %b expected %b",
                               i, uart_txd, probe[i]);
                    @(negedge clk);
                end
            end
            // Stop bit high, one full bit period.
            repeat (CLKS_PER_BIT) begin
                if (uart_txd !== 1'b1) $fatal(1, "tx stop bit must be high");
                @(negedge clk);
            end
            while (tx_ready !== 1'b1) @(negedge clk);
        end

        // D. Busy hold: changing tx_data mid-byte must not corrupt the byte
        // already accepted; the next byte is taken only after ready returns.
        $display("stage D t=%0d", $time);
        loopback = 1'b1;
        begin
            @(negedge clk);
            while (tx_ready !== 1'b1) @(negedge clk);
            tx_data  = 8'h33;
            tx_valid = 1'b1;
            @(negedge clk);
            while (tx_ready === 1'b1) @(negedge clk);
            // Busy: alter the data bus; current latched byte must be sent.
            tx_data = 8'hCC;
            while (rx_flag !== 1'b1) @(negedge clk);
            if (rx_buf !== 8'h33)
                $fatal(1, "busy hold: got %h expected 33", rx_buf);
            rx_flag = 1'b0;
            @(negedge clk);
            tx_valid = 1'b0;
            while (tx_ready !== 1'b1) @(negedge clk);
            send_loopback(8'hCC);
        end

        // E. Reset mid-transmission, then recover with a fresh full byte.
        $display("stage E t=%0d", $time);
        begin
            @(negedge clk);
            while (tx_ready !== 1'b1) @(negedge clk);
            tx_data  = 8'h3C;
            tx_valid = 1'b1;
            @(negedge clk);
            while (tx_ready === 1'b1) @(negedge clk);
            // Abort with reset while the byte is being shifted out.
            rst_n = 1'b0;
            repeat (4) @(negedge clk);
            if (tx_ready !== 1'b1 || uart_txd !== 1'b1)
                $fatal(1, "reset must return TX to idle high/ready");
            rst_n = 1'b1;
            tx_valid = 1'b0;
            repeat (2) @(negedge clk);
            send_loopback(8'h3C);
        end

        $display("PASS: uart loopback, bit order, tx timing, hold, reset");
        $finish;
    end

    // Guard: stop the simulation if it hangs.
    initial begin
        #2000000;
        $fatal(1, "timeout: tb_uart did not finish");
    end
endmodule
