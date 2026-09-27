`timescale 1ns/1ps

module data_feeder #(
    parameter integer INPUT_ADDR_WIDTH  = 12,
    parameter integer WEIGHT_ADDR_WIDTH = 13
)(
    // ============================================================
    // Clock / Reset / Clear
    // ============================================================
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         clear,

    // ============================================================
    // Feeder Control
    // ============================================================
    input  wire                         start,
    output wire                         busy,
    output reg                          data_valid,

    // ============================================================
    // Base Addresses
    //
    // The feeder collects 4 consecutive activations and
    // 4 consecutive weights beginning at these addresses.
    // ============================================================
    input  wire [INPUT_ADDR_WIDTH-1:0]  input_base_addr,
    input  wire [WEIGHT_ADDR_WIDTH-1:0] weight_base_addr,

    // ============================================================
    // Input Buffer Read Interface
    // ============================================================
    output reg                          input_read_en,
    output reg  [INPUT_ADDR_WIDTH-1:0]  input_read_addr,
    input  wire signed [7:0]            input_read_data,

    // ============================================================
    // Weight Buffer Read Interface
    // ============================================================
    output reg                          weight_read_en,
    output reg  [WEIGHT_ADDR_WIDTH-1:0] weight_read_addr,
    input  wire signed [7:0]            weight_read_data,

    // ============================================================
    // Packed Data to PE Array
    //
    // activation_bus:
    //   [7:0]   = activation 0
    //   [15:8]  = activation 1
    //   [23:16] = activation 2
    //   [31:24] = activation 3
    //
    // weight_bus:
    //   [7:0]   = weight 0
    //   [15:8]  = weight 1
    //   [23:16] = weight 2
    //   [31:24] = weight 3
    // ============================================================
    output reg  [31:0]                  activation_bus,
    output reg  [31:0]                  weight_bus
);

    // ============================================================
    // State Encoding
    //
    // Buffers use synchronous reads.
    //
    // READ0 issues address 0.
    // READ1 captures data 0 and issues address 1.
    // READ2 captures data 1 and issues address 2.
    // READ3 captures data 2 and issues address 3.
    // CAPTURE_LAST captures data 3 and pulses data_valid.
    // ============================================================
    localparam [2:0] IDLE         = 3'd0;
    localparam [2:0] READ0        = 3'd1;
    localparam [2:0] READ1        = 3'd2;
    localparam [2:0] READ2        = 3'd3;
    localparam [2:0] READ3        = 3'd4;
    localparam [2:0] CAPTURE_LAST = 3'd5;

    reg [2:0] state;

    assign busy = (state != IDLE);

    // ============================================================
    // Buffer Read Control
    // ============================================================
    always @(*) begin

        input_read_en    = 1'b0;
        weight_read_en   = 1'b0;

        input_read_addr  = input_base_addr;
        weight_read_addr = weight_base_addr;

        case (state)

            READ0: begin
                input_read_en    = 1'b1;
                weight_read_en   = 1'b1;

                input_read_addr  = input_base_addr;
                weight_read_addr = weight_base_addr;
            end

            READ1: begin
                input_read_en    = 1'b1;
                weight_read_en   = 1'b1;

                input_read_addr  = input_base_addr + 1'b1;
                weight_read_addr = weight_base_addr + 1'b1;
            end

            READ2: begin
                input_read_en    = 1'b1;
                weight_read_en   = 1'b1;

                input_read_addr  = input_base_addr + 2'd2;
                weight_read_addr = weight_base_addr + 2'd2;
            end

            READ3: begin
                input_read_en    = 1'b1;
                weight_read_en   = 1'b1;

                input_read_addr  = input_base_addr + 2'd3;
                weight_read_addr = weight_base_addr + 2'd3;
            end

            default: begin
                input_read_en    = 1'b0;
                weight_read_en   = 1'b0;
            end

        endcase
    end

    // ============================================================
    // State / Data Capture Logic
    // ============================================================
    always @(posedge clk) begin

        if (rst) begin

            state          <= IDLE;
            data_valid     <= 1'b0;
            activation_bus <= 32'd0;
            weight_bus     <= 32'd0;

        end
        else if (clear) begin

            state          <= IDLE;
            data_valid     <= 1'b0;
            activation_bus <= 32'd0;
            weight_bus     <= 32'd0;

        end
        else begin

            // data_valid is a one-clock pulse.
            data_valid <= 1'b0;

            case (state)

                // ------------------------------------------------
                // Wait for a new 4-value fetch request.
                // ------------------------------------------------
                IDLE: begin

                    if (start) begin
                        activation_bus <= 32'd0;
                        weight_bus     <= 32'd0;
                        state          <= READ0;
                    end

                end

                // ------------------------------------------------
                // READ0:
                // Address 0 is being issued to both buffers.
                // No valid returned data is captured yet.
                // ------------------------------------------------
                READ0: begin
                    state <= READ1;
                end

                // ------------------------------------------------
                // READ1:
                // Buffer outputs now contain address 0.
                // ------------------------------------------------
                READ1: begin

                    activation_bus[7:0] <= input_read_data;
                    weight_bus[7:0]     <= weight_read_data;

                    state <= READ2;

                end

                // ------------------------------------------------
                // READ2:
                // Buffer outputs now contain address 1.
                // ------------------------------------------------
                READ2: begin

                    activation_bus[15:8] <= input_read_data;
                    weight_bus[15:8]     <= weight_read_data;

                    state <= READ3;

                end

                // ------------------------------------------------
                // READ3:
                // Buffer outputs now contain address 2.
                // ------------------------------------------------
                READ3: begin

                    activation_bus[23:16] <= input_read_data;
                    weight_bus[23:16]     <= weight_read_data;

                    state <= CAPTURE_LAST;

                end

                // ------------------------------------------------
                // CAPTURE_LAST:
                // Buffer outputs now contain address 3.
                // Pack the final bytes and indicate that the
                // complete 4x activation / 4x weight bundle is ready.
                // ------------------------------------------------
                CAPTURE_LAST: begin

                    activation_bus[31:24] <= input_read_data;
                    weight_bus[31:24]     <= weight_read_data;

                    data_valid <= 1'b1;
                    state      <= IDLE;

                end

                // ------------------------------------------------
                // Illegal-state recovery
                // ------------------------------------------------
                default: begin
                    state <= IDLE;
                end

            endcase

        end

    end

endmodule
