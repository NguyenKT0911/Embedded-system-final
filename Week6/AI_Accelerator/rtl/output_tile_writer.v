`timescale 1ns/1ps

module output_tile_writer #(
    parameter integer OUTPUT_ADDR_WIDTH = 14
)(
    // ============================================================
    // Clock / Reset / Clear
    // ============================================================
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         clear,

    // ============================================================
    // Completed Tile from Convolution Engine
    // ============================================================
    input  wire                         tile_ready,
    output reg                          tile_accept,

    input  wire [15:0]                  tile_oh,
    input  wire [15:0]                  tile_ow_base,
    input  wire [15:0]                  tile_oc_base,

    input  wire [15:0]                  out_h,
    input  wire [15:0]                  out_w,
    input  wire [15:0]                  cout,

    input  wire                         relu_en,

    // 16 x signed INT32 PE accumulators, row-major:
    //   row = output-position lane (0..3)
    //   col = output-channel lane  (0..3)
    input  wire [511:0]                 accumulator_bus,

    // ============================================================
    // Indexed Output-Buffer Write Interface
    //
    // Output layout:
    //   [COUT][OUT_H][OUT_W]
    //
    // flat index:
    //   ((oc * out_h) + oh) * out_w + ow
    // ============================================================
    output reg  [OUTPUT_ADDR_WIDTH-1:0] write_addr,
    output reg  signed [31:0]           write_data,
    output reg                          write_valid,

    // ============================================================
    // Status
    // ============================================================
    output wire                         busy
);

    // ============================================================
    // FSM
    //
    // WAIT_RELEASE prevents the same tile from being captured twice.
    // The convolution engine keeps tile_ready high until it samples
    // tile_accept on a rising edge.
    // ============================================================
    localparam [2:0] IDLE         = 3'd0;
    localparam [2:0] WRITE        = 3'd1;
    localparam [2:0] ACK          = 3'd2;
    localparam [2:0] WAIT_RELEASE = 3'd3;

    reg [2:0] state;

    assign busy = (state != IDLE);

    // ============================================================
    // Latched Tile
    // ============================================================
    reg [511:0] accumulator_latched;

    reg [15:0] tile_oh_latched;
    reg [15:0] tile_ow_base_latched;
    reg [15:0] tile_oc_base_latched;

    reg [15:0] out_h_latched;
    reg [15:0] out_w_latched;
    reg [15:0] cout_latched;

    reg        relu_en_latched;

    // ============================================================
    // Lane Counter
    // ============================================================
    reg [4:0] lane_index;

    reg [2:0] row_lane;
    reg [2:0] channel_lane;

    reg [15:0] current_ow;
    reg [15:0] current_oc;

    reg signed [31:0] selected_accumulator;

    reg [31:0] flat_index;

    reg lane_valid;

    // ============================================================
    // ReLU
    // ============================================================
    wire signed [31:0] relu_data;

    relu_unit u_relu (
        .relu_en(relu_en_latched),
        .data_in(selected_accumulator),
        .data_out(relu_data)
    );

    // ============================================================
    // Current-Lane Decode / Write Generation / Handshake Output
    // ============================================================
    always @(*) begin

        write_addr            = {OUTPUT_ADDR_WIDTH{1'b0}};
        write_data            = 32'sd0;
        write_valid           = 1'b0;

        tile_accept           = 1'b0;

        row_lane              = 3'd0;
        channel_lane          = 3'd0;

        current_ow            = 16'd0;
        current_oc            = 16'd0;

        selected_accumulator  = 32'sd0;
        flat_index            = 32'd0;

        lane_valid            = 1'b0;

        // One full clock of acknowledge.
        if (state == ACK)
            tile_accept = 1'b1;

        if (state == WRITE) begin

            row_lane     = lane_index[4:2];
            channel_lane = {1'b0, lane_index[1:0]};

            current_ow = tile_ow_base_latched + row_lane;
            current_oc = tile_oc_base_latched + channel_lane;

            case (lane_index)

                5'd0:  selected_accumulator = accumulator_latched[31:0];
                5'd1:  selected_accumulator = accumulator_latched[63:32];
                5'd2:  selected_accumulator = accumulator_latched[95:64];
                5'd3:  selected_accumulator = accumulator_latched[127:96];

                5'd4:  selected_accumulator = accumulator_latched[159:128];
                5'd5:  selected_accumulator = accumulator_latched[191:160];
                5'd6:  selected_accumulator = accumulator_latched[223:192];
                5'd7:  selected_accumulator = accumulator_latched[255:224];

                5'd8:  selected_accumulator = accumulator_latched[287:256];
                5'd9:  selected_accumulator = accumulator_latched[319:288];
                5'd10: selected_accumulator = accumulator_latched[351:320];
                5'd11: selected_accumulator = accumulator_latched[383:352];

                5'd12: selected_accumulator = accumulator_latched[415:384];
                5'd13: selected_accumulator = accumulator_latched[447:416];
                5'd14: selected_accumulator = accumulator_latched[479:448];
                5'd15: selected_accumulator = accumulator_latched[511:480];

                default:
                    selected_accumulator = 32'sd0;

            endcase

            lane_valid =
                (current_ow < out_w_latched) &&
                (current_oc < cout_latched) &&
                (tile_oh_latched < out_h_latched);

            if (lane_valid) begin

                flat_index =
                    ((current_oc * out_h_latched) + tile_oh_latched)
                    * out_w_latched
                    + current_ow;

                write_addr  = flat_index[OUTPUT_ADDR_WIDTH-1:0];
                write_data  = relu_data;
                write_valid = 1'b1;

            end

        end

    end

    // ============================================================
    // Sequential Control
    // ============================================================
    always @(posedge clk) begin

        if (rst) begin

            state <= IDLE;

            accumulator_latched <= 512'd0;

            tile_oh_latched      <= 16'd0;
            tile_ow_base_latched <= 16'd0;
            tile_oc_base_latched <= 16'd0;

            out_h_latched <= 16'd0;
            out_w_latched <= 16'd0;
            cout_latched  <= 16'd0;

            relu_en_latched <= 1'b0;

            lane_index <= 5'd0;

        end
        else if (clear) begin

            state <= IDLE;

            accumulator_latched <= 512'd0;

            tile_oh_latched      <= 16'd0;
            tile_ow_base_latched <= 16'd0;
            tile_oc_base_latched <= 16'd0;

            out_h_latched <= 16'd0;
            out_w_latched <= 16'd0;
            cout_latched  <= 16'd0;

            relu_en_latched <= 1'b0;

            lane_index <= 5'd0;

        end
        else begin

            case (state)

                // ------------------------------------------------
                // Capture a completed tile.
                // ------------------------------------------------
                IDLE: begin

                    if (tile_ready) begin

                        accumulator_latched <= accumulator_bus;

                        tile_oh_latched      <= tile_oh;
                        tile_ow_base_latched <= tile_ow_base;
                        tile_oc_base_latched <= tile_oc_base;

                        out_h_latched <= out_h;
                        out_w_latched <= out_w;
                        cout_latched  <= cout;

                        relu_en_latched <= relu_en;

                        lane_index <= 5'd0;

                        state <= WRITE;

                    end

                end

                // ------------------------------------------------
                // Scan all 16 PE lanes.
                // ------------------------------------------------
                WRITE: begin

                    if (lane_index == 5'd15) begin
                        state <= ACK;
                    end
                    else begin
                        lane_index <= lane_index + 5'd1;
                    end

                end

                // ------------------------------------------------
                // Hold tile_accept high for one clock.
                // ------------------------------------------------
                ACK: begin
                    state <= WAIT_RELEASE;
                end

                // ------------------------------------------------
                // Wait until producer drops tile_ready.
                // This avoids re-latching the same completed tile.
                // ------------------------------------------------
                WAIT_RELEASE: begin

                    if (!tile_ready)
                        state <= IDLE;

                end

                default: begin
                    state <= IDLE;
                end

            endcase

        end

    end

endmodule
