`timescale 1ns/1ps

module conv_data_feeder_4x4 #(
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
    // Four Independent Activation Addresses
    // ============================================================
    input  wire [INPUT_ADDR_WIDTH-1:0]  input_addr_0,
    input  wire [INPUT_ADDR_WIDTH-1:0]  input_addr_1,
    input  wire [INPUT_ADDR_WIDTH-1:0]  input_addr_2,
    input  wire [INPUT_ADDR_WIDTH-1:0]  input_addr_3,
    input  wire [3:0]                   input_valid_mask,

    // ============================================================
    // Four Independent Weight Addresses
    // ============================================================
    input  wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr_0,
    input  wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr_1,
    input  wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr_2,
    input  wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr_3,
    input  wire [3:0]                   weight_valid_mask,

    // ============================================================
    // Single-Port Input Buffer Read Interface
    // ============================================================
    output reg                          input_read_en,
    output reg  [INPUT_ADDR_WIDTH-1:0]  input_read_addr,
    input  wire signed [7:0]            input_read_data,

    // ============================================================
    // Single-Port Weight Buffer Read Interface
    // ============================================================
    output reg                          weight_read_en,
    output reg  [WEIGHT_ADDR_WIDTH-1:0] weight_read_addr,
    input  wire signed [7:0]            weight_read_data,

    // ============================================================
    // Packed Bundle to PE Array
    //
    // [7:0]   = lane 0
    // [15:8]  = lane 1
    // [23:16] = lane 2
    // [31:24] = lane 3
    //
    // Invalid activation lanes are forced to 0 for padding.
    // Invalid weight lanes are forced to 0 for COUT tail lanes.
    // ============================================================
    output reg  [31:0]                  activation_bus,
    output reg  [31:0]                  weight_bus
);

    // ============================================================
    // FSM
    //
    // Buffers use synchronous reads, so each address is issued
    // first and its returned byte is captured on a later state.
    // ============================================================
    localparam [2:0] IDLE     = 3'd0;
    localparam [2:0] ISSUE0   = 3'd1;
    localparam [2:0] ISSUE1   = 3'd2;
    localparam [2:0] ISSUE2   = 3'd3;
    localparam [2:0] ISSUE3   = 3'd4;
    localparam [2:0] CAPTURE3 = 3'd5;

    reg [2:0] state;

    assign busy = (state != IDLE);

    // ============================================================
    // Snapshot the whole request at START.
    //
    // This is important because the convolution sequencer/address
    // generator may change its indices while the feeder is busy.
    // ============================================================
    reg [INPUT_ADDR_WIDTH-1:0]  input_addr_latched_0;
    reg [INPUT_ADDR_WIDTH-1:0]  input_addr_latched_1;
    reg [INPUT_ADDR_WIDTH-1:0]  input_addr_latched_2;
    reg [INPUT_ADDR_WIDTH-1:0]  input_addr_latched_3;
    reg [3:0]                   input_mask_latched;

    reg [WEIGHT_ADDR_WIDTH-1:0] weight_addr_latched_0;
    reg [WEIGHT_ADDR_WIDTH-1:0] weight_addr_latched_1;
    reg [WEIGHT_ADDR_WIDTH-1:0] weight_addr_latched_2;
    reg [WEIGHT_ADDR_WIDTH-1:0] weight_addr_latched_3;
    reg [3:0]                   weight_mask_latched;

    // ============================================================
    // Buffer Read Control
    // ============================================================
    always @(*) begin

        input_read_en    = 1'b0;
        input_read_addr  = {INPUT_ADDR_WIDTH{1'b0}};

        weight_read_en   = 1'b0;
        weight_read_addr = {WEIGHT_ADDR_WIDTH{1'b0}};

        case (state)

            ISSUE0: begin
                input_read_en    = input_mask_latched[0];
                input_read_addr  = input_addr_latched_0;

                weight_read_en   = weight_mask_latched[0];
                weight_read_addr = weight_addr_latched_0;
            end

            ISSUE1: begin
                input_read_en    = input_mask_latched[1];
                input_read_addr  = input_addr_latched_1;

                weight_read_en   = weight_mask_latched[1];
                weight_read_addr = weight_addr_latched_1;
            end

            ISSUE2: begin
                input_read_en    = input_mask_latched[2];
                input_read_addr  = input_addr_latched_2;

                weight_read_en   = weight_mask_latched[2];
                weight_read_addr = weight_addr_latched_2;
            end

            ISSUE3: begin
                input_read_en    = input_mask_latched[3];
                input_read_addr  = input_addr_latched_3;

                weight_read_en   = weight_mask_latched[3];
                weight_read_addr = weight_addr_latched_3;
            end

            default: begin
                input_read_en    = 1'b0;
                weight_read_en   = 1'b0;
            end

        endcase
    end

    // ============================================================
    // FSM / Bundle Assembly
    // ============================================================
    always @(posedge clk) begin

        if (rst) begin

            state          <= IDLE;
            data_valid     <= 1'b0;

            activation_bus <= 32'd0;
            weight_bus     <= 32'd0;

            input_addr_latched_0 <= {INPUT_ADDR_WIDTH{1'b0}};
            input_addr_latched_1 <= {INPUT_ADDR_WIDTH{1'b0}};
            input_addr_latched_2 <= {INPUT_ADDR_WIDTH{1'b0}};
            input_addr_latched_3 <= {INPUT_ADDR_WIDTH{1'b0}};
            input_mask_latched   <= 4'b0000;

            weight_addr_latched_0 <= {WEIGHT_ADDR_WIDTH{1'b0}};
            weight_addr_latched_1 <= {WEIGHT_ADDR_WIDTH{1'b0}};
            weight_addr_latched_2 <= {WEIGHT_ADDR_WIDTH{1'b0}};
            weight_addr_latched_3 <= {WEIGHT_ADDR_WIDTH{1'b0}};
            weight_mask_latched   <= 4'b0000;

        end
        else if (clear) begin

            state          <= IDLE;
            data_valid     <= 1'b0;

            activation_bus <= 32'd0;
            weight_bus     <= 32'd0;

            input_mask_latched  <= 4'b0000;
            weight_mask_latched <= 4'b0000;

        end
        else begin

            // One-clock pulse when all four lanes are assembled.
            data_valid <= 1'b0;

            case (state)

                // ------------------------------------------------
                // Accept and snapshot a new address request.
                // ------------------------------------------------
                IDLE: begin

                    if (start) begin

                        input_addr_latched_0 <= input_addr_0;
                        input_addr_latched_1 <= input_addr_1;
                        input_addr_latched_2 <= input_addr_2;
                        input_addr_latched_3 <= input_addr_3;
                        input_mask_latched   <= input_valid_mask;

                        weight_addr_latched_0 <= weight_addr_0;
                        weight_addr_latched_1 <= weight_addr_1;
                        weight_addr_latched_2 <= weight_addr_2;
                        weight_addr_latched_3 <= weight_addr_3;
                        weight_mask_latched   <= weight_valid_mask;

                        activation_bus <= 32'd0;
                        weight_bus     <= 32'd0;

                        state <= ISSUE0;

                    end

                end

                // ------------------------------------------------
                // Address lane 0 is being presented to the buffers.
                // ------------------------------------------------
                ISSUE0: begin
                    state <= ISSUE1;
                end

                // ------------------------------------------------
                // Capture lane 0 while issuing lane 1.
                // ------------------------------------------------
                ISSUE1: begin

                    if (input_mask_latched[0])
                        activation_bus[7:0] <= input_read_data;
                    else
                        activation_bus[7:0] <= 8'd0;

                    if (weight_mask_latched[0])
                        weight_bus[7:0] <= weight_read_data;
                    else
                        weight_bus[7:0] <= 8'd0;

                    state <= ISSUE2;

                end

                // ------------------------------------------------
                // Capture lane 1 while issuing lane 2.
                // ------------------------------------------------
                ISSUE2: begin

                    if (input_mask_latched[1])
                        activation_bus[15:8] <= input_read_data;
                    else
                        activation_bus[15:8] <= 8'd0;

                    if (weight_mask_latched[1])
                        weight_bus[15:8] <= weight_read_data;
                    else
                        weight_bus[15:8] <= 8'd0;

                    state <= ISSUE3;

                end

                // ------------------------------------------------
                // Capture lane 2 while issuing lane 3.
                // ------------------------------------------------
                ISSUE3: begin

                    if (input_mask_latched[2])
                        activation_bus[23:16] <= input_read_data;
                    else
                        activation_bus[23:16] <= 8'd0;

                    if (weight_mask_latched[2])
                        weight_bus[23:16] <= weight_read_data;
                    else
                        weight_bus[23:16] <= 8'd0;

                    state <= CAPTURE3;

                end

                // ------------------------------------------------
                // Capture final lane and finish one bundle.
                // ------------------------------------------------
                CAPTURE3: begin

                    if (input_mask_latched[3])
                        activation_bus[31:24] <= input_read_data;
                    else
                        activation_bus[31:24] <= 8'd0;

                    if (weight_mask_latched[3])
                        weight_bus[31:24] <= weight_read_data;
                    else
                        weight_bus[31:24] <= 8'd0;

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
