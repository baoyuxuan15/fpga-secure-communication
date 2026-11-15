`timescale 1ns/1ps
// Independent UART testbench for role 2.
//   A. Loopback TX -> RX: 00, 55, AA, FF, check data and receive count.
//   B. Direct serial stimulus into RX: verify LSB-first bit order.
//   C. Monitor TX line directly: start/data/stop each exactly 434 clocks.
//   D. Hold tx_valid while busy: current byte finishes before the next is taken.
//   E. Reset in the middle of the data bits, then recover with a fresh byte.
//   F. Back-to-back frames with no idle gap: both bytes are received.
//   G. Sender two clocks per bit fast (432): four bytes are still received.
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

    // Drive one 8N1 byte straight onto the RX line, LSB first, at the nominal
    // 434 clocks per bit.
    task drive_rx_byte;
        input [7:0] tx_byte;
        begin
            drive_rx_byte_w(tx_byte, CLKS_PER_BIT);
        end
    endtask

    // Same as above with an explicit bit width, to model a sender whose baud
    // rate is off by a clock or two.
    task drive_rx_byte_w;
        input [7:0]   tx_byte;
        input integer bit_clks;
        integer i;
        begin
            // Start bit (low)
            rx_drive = 1'b0;
            repeat (bit_clks) @(negedge clk);
            // Data bits, bit 0 first
            for (i = 0; i < 8; i = i + 1) begin
                rx_drive = tx_byte[i];
                repeat (bit_clks) @(negedge clk);
            end
            // Stop bit (high)
            rx_drive = 1'b1;
            repeat (bit_clks) @(negedge clk);
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

        // C. Monitor the TX line directly. Every segment - start bit, the eight
        // data bits and the stop bit - must last exactly 434 clocks, and ready
        // must come back only after the full stop bit.
        $display("stage C t=%0d", $time);
        begin
            integer i, w, tprev;
            reg     prev;
            reg [7:0] probe;
            probe = 8'h55;  // 0101 0101: every segment differs from its neighbour
            @(negedge clk);
            while (tx_ready !== 1'b1) @(negedge clk);
            tx_data  = probe;
            tx_valid = 1'b1;
            @(negedge clk);
            while (tx_ready === 1'b1) @(negedge clk);
            tx_valid = 1'b0;

            // Wait for the start edge, then time each segment.
            while (uart_txd === 1'b1) @(negedge clk);
            prev  = 1'b0;
            tprev = $time;
            for (i = 0; i < 9; i = i + 1) begin
                while (uart_txd === prev) @(negedge clk);
                // "prev" was the level of segment i before this transition.
                if (i == 0) begin
                    if (prev !== 1'b0) $fatal(1, "tx start bit must be low");
                end else begin
                    if (prev !== probe[i-1])
                        $fatal(1, "tx bit %0d: line %b expected %b",
                               i-1, prev, probe[i-1]);
                end
                w = ($time - tprev) / 20;
                if (w !== CLKS_PER_BIT)
                    $fatal(1, "tx segment %0d lasts %0d clocks, expected 434",
                           i, w);
                prev  = uart_txd;
                tprev = $time;
            end
            // Last measured transition ends bit 7: the line is now the stop bit.
            if (prev !== 1'b1) $fatal(1, "tx stop bit must be high");
            while (tx_ready !== 1'b1) @(negedge clk);
            w = ($time - tprev) / 20;
            if (w !== CLKS_PER_BIT)
                $fatal(1, "tx stop bit / ready latency %0d, expected 434", w);
            $display("tx segment width check: 434 clocks for all 10 segments");
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

        // E. Reset in the middle of the data bits, then recover with a
        // fresh full byte. Start bit (434) plus two data bits puts the reset
        // inside bit 2, while the line is actually carrying data.
        $display("stage E t=%0d", $time);
        begin
            integer base;
            base = rx_count;
            @(negedge clk);
            while (tx_ready !== 1'b1) @(negedge clk);
            tx_data  = 8'h3C;
            tx_valid = 1'b1;
            @(negedge clk);
            while (tx_ready === 1'b1) @(negedge clk);
            tx_valid = 1'b0;
            repeat (434 + 2 * 434) @(negedge clk);
            // Abort with reset while the byte is being shifted out.
            rst_n = 1'b0;
            repeat (4) @(negedge clk);
            if (tx_ready !== 1'b1 || uart_txd !== 1'b1)
                $fatal(1, "reset must return TX to idle high/ready");
            if (rx_count !== base)
                $fatal(1, "reset must drop the partial byte");
            rst_n = 1'b1;
            tx_valid = 1'b0;
            rx_flag  = 1'b0;
            repeat (2) @(negedge clk);
            send_loopback(8'h3C);
        end

        // F. Back-to-back frames: the stop bit of the first byte is followed
        // immediately by the start bit of the second. Both must be received.
        $display("stage F t=%0d", $time);
        loopback = 1'b0;
        begin
            integer base;
            base = rx_count;
            rx_flag = 1'b0;
            drive_rx_byte(8'h3A);
            drive_rx_byte(8'hC5);
            @(negedge clk);
            if (rx_count !== base + 2)
                $fatal(1, "back-to-back: expected %0d pulses, got %0d",
                       base + 2, rx_count);
            if (rx_buf !== 8'hC5)
                $fatal(1, "back-to-back: got %h expected C5", rx_buf);
            rx_flag = 1'b0;
        end

        // G. A sender running two clocks per bit fast (432 instead of 434)
        // must still be decoded for all four bytes.
        $display("stage G t=%0d", $time);
        begin
            integer base;
            base = rx_count;
            rx_flag = 1'b0;
            drive_rx_byte_w(8'hA5, CLKS_PER_BIT - 2);
            drive_rx_byte_w(8'h34, CLKS_PER_BIT - 2);
            drive_rx_byte_w(8'hD2, CLKS_PER_BIT - 2);
            drive_rx_byte_w(8'h81, CLKS_PER_BIT - 2);
            @(negedge clk);
            if (rx_count !== base + 4)
                $fatal(1, "fast sender: expected %0d pulses, got %0d",
                       base + 4, rx_count);
            if (rx_buf !== 8'h81)
                $fatal(1, "fast sender: got %h expected 81", rx_buf);
            rx_flag = 1'b0;
        end

        $display("PASS: uart loopback, bit order, 434-clock timing, hold, reset, back-to-back");
        $finish;
    end

    // Guard: stop the simulation if it hangs.
    initial begin
        #2000000;
        $fatal(1, "timeout: tb_uart did not finish");
    end
endmodule
