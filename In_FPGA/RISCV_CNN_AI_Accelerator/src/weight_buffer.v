`timescale 1ns/1ps

module weight_buffer #(
    parameter integer MAX_VALUES = 4608,
    parameter integer ADDR_WIDTH = 13
)(
    // ============================================================
    // Clock / Reset / Clear
    // ============================================================
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         clear,

    // ============================================================
    // Write Interface from MMIO
    //
    // One 32-bit word contains four packed INT8 weights:
    //   [7:0]   = weight n
    //   [15:8]  = weight n+1
    //   [23:16] = weight n+2
    //   [31:24] = weight n+3
    // ============================================================
    input  wire [31:0]                  write_data,
    input  wire                         write_valid,

    // ============================================================
    // Read Interface to Compute Core
    //
    // Synchronous read:
    //   read_en=1 at a rising edge
    //   -> read_data updates immediately after that edge
    // ============================================================
    input  wire                         read_en,
    input  wire [ADDR_WIDTH-1:0]        read_addr,
    output reg  signed [7:0]            read_data,

    // ============================================================
    // Buffer Status
    // ============================================================
    output reg  [31:0]                  stored_count,
    output wire                         full,
    output reg                          overflow_error
);

    // ============================================================
    // Packed Weight Memory
    // ============================================================
    localparam integer WORD_COUNT = (MAX_VALUES + 3) / 4;
    reg [31:0] mem [0:WORD_COUNT-1];

    reg [31:0] read_word;
    reg [1:0]  read_byte_index;
    reg        read_in_range;

    // Buffer is full when all weight slots are occupied.
    assign full = (stored_count >= MAX_VALUES);

    // Byte selection is performed after the registered 32-bit RAM read.
    always @(*) begin
        if (!read_in_range) begin
            read_data = 8'sd0;
        end
        else begin
            case (read_byte_index)
                2'd0: read_data = $signed(read_word[7:0]);
                2'd1: read_data = $signed(read_word[15:8]);
                2'd2: read_data = $signed(read_word[23:16]);
                2'd3: read_data = $signed(read_word[31:24]);
                default: read_data = 8'sd0;
            endcase
        end
    end

    // ============================================================
    // Sequential Logic
    // ============================================================
    always @(posedge clk) begin

        if (rst) begin

            stored_count   <= 32'd0;
            read_word      <= 32'd0;
            read_byte_index <= 2'd0;
            read_in_range  <= 1'b0;
            overflow_error <= 1'b0;

        end
        else if (clear) begin

            // Logical clear only.
            // The memory array does not need to be physically erased.
            stored_count   <= 32'd0;
            read_word      <= 32'd0;
            read_byte_index <= 2'd0;
            read_in_range  <= 1'b0;
            overflow_error <= 1'b0;

        end
        else begin

            // ----------------------------------------------------
            // Write four packed INT8 weights.
            // ----------------------------------------------------
            if (write_valid) begin

                if (stored_count <= (MAX_VALUES - 4)) begin

                    mem[stored_count[ADDR_WIDTH-1:2]] <= write_data;

                    stored_count <= stored_count + 32'd4;

                end
                else begin

                    // Sticky error until reset/clear.
                    overflow_error <= 1'b1;

                end

            end

            // ----------------------------------------------------
            // Synchronous INT8 read for compute datapath.
            // ----------------------------------------------------
            if (read_en) begin

                read_word       <= mem[read_addr[ADDR_WIDTH-1:2]];
                read_byte_index <= read_addr[1:0];
                read_in_range   <= (read_addr < stored_count);

            end

        end

    end

endmodule
