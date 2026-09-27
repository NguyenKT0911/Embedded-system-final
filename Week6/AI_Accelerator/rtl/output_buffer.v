`timescale 1ns/1ps

module output_buffer #(
    parameter integer MAX_VALUES = 12544,
    parameter integer ADDR_WIDTH = 14
)(
    // ============================================================
    // Clock / Reset / Clear
    // ============================================================
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         clear,

    // ============================================================
    // Indexed Write Interface from Output Tile Writer
    //
    // write_addr follows flattened output layout:
    //   [COUT][OUT_H][OUT_W]
    // ============================================================
    input  wire [ADDR_WIDTH-1:0]        write_addr,
    input  wire signed [31:0]           write_data,
    input  wire                         write_valid,

    // ============================================================
    // Sequential Read Interface to MMIO
    //
    // read_data always shows mem[read_index].
    // read_next advances to the next output value.
    // ============================================================
    output reg  signed [31:0]           read_data,
    input  wire                         read_next,

    // ============================================================
    // Buffer Status
    // ============================================================
    output reg  [31:0]                  stored_count,
    output reg  [31:0]                  read_index,

    output wire                         empty,
    output wire                         full,

    output reg                          overflow_error
);

    // ============================================================
    // Signed INT32 Output Memory
    // ============================================================
    // One synchronous read port plus one synchronous write port is used so
    // FPGA synthesis can map this large array to true dual-port block RAM.
    reg signed [31:0] mem [0:MAX_VALUES-1];

    // ============================================================
    // Status Flags
    //
    // stored_count counts successful writes.
    // In the current convolution engine every output address is
    // written exactly once, so after DONE:
    //   stored_count == total output values.
    // ============================================================
    assign empty = (read_index >= stored_count);
    assign full  = (stored_count >= MAX_VALUES);

    // Prefetch the next sequential word on the same edge that consumes the
    // current word. The SoC inserts a bubble after OUTPUT_DATA, so the
    // registered value is ready before a following CPU load.
    wire [31:0] prefetch_index =
        read_index + (read_next ? 32'd1 : 32'd0);

    // ============================================================
    // Sequential Write / Read-Pointer Logic
    // ============================================================
    always @(posedge clk) begin

        if (rst) begin

            stored_count   <= 32'd0;
            read_index     <= 32'd0;
            read_data      <= 32'sd0;
            overflow_error <= 1'b0;

        end
        else if (clear) begin

            // Logical clear only. RAM contents need not be erased.
            stored_count   <= 32'd0;
            read_index     <= 32'd0;
            read_data      <= 32'sd0;
            overflow_error <= 1'b0;

        end
        else begin

            // ----------------------------------------------------
            // Indexed write from output_tile_writer.
            // ----------------------------------------------------
            if (write_valid) begin

                if ((write_addr < MAX_VALUES) &&
                    (stored_count < MAX_VALUES)) begin

                    mem[write_addr] <= write_data;
                    stored_count    <= stored_count + 32'd1;

                end
                else begin

                    // Sticky until reset/clear.
                    overflow_error <= 1'b1;

                end

            end

            // ----------------------------------------------------
            // Sequential MMIO read pointer.
            // ----------------------------------------------------
            if (read_next) begin

                if (read_index < stored_count)
                    read_index <= read_index + 32'd1;

            end

            // Synchronous B-RAM-friendly read/prefetch port.
            if ((prefetch_index < stored_count) &&
                (prefetch_index < MAX_VALUES))
                read_data <= mem[prefetch_index[ADDR_WIDTH-1:0]];
            else
                read_data <= 32'sd0;

        end

    end

endmodule
