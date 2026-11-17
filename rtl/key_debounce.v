// Active-low mechanical key: synchronize, qualify both edges, pulse on press.
module key_debounce #(
    parameter integer DEBOUNCE_CYCLES = 1000000 // 20 ms at 50 MHz; >= 1
) (
    input wire clk, rst_n, key_n,
    output reg pressed,
    output wire held
);
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg key_meta, key_sync;
    reg stable_n;
    reg [31:0] qualify_count;
    assign held = !stable_n;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_meta <= 1'b1;
            key_sync <= 1'b1;
            stable_n <= 1'b1;
            qualify_count <= 32'd0;
            pressed <= 1'b0;
        end else begin
            key_meta <= key_n;
            key_sync <= key_meta;
            pressed <= 1'b0;
            if (key_sync == stable_n)
                qualify_count <= 32'd0;
            else if (qualify_count == DEBOUNCE_CYCLES - 1) begin
                qualify_count <= 32'd0;
                stable_n <= key_sync;
                pressed <= !key_sync;
            end else
                qualify_count <= qualify_count + 32'd1;
        end
    end
endmodule
