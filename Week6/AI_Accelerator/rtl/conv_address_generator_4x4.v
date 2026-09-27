`timescale 1ns/1ps

module conv_address_generator_4x4 #(
    parameter integer INPUT_ADDR_WIDTH  = 12,
    parameter integer WEIGHT_ADDR_WIDTH = 13
)(
    // ============================================================
    // Convolution Configuration
    // ============================================================
    input  wire [15:0] input_h,
    input  wire [15:0] input_w,
    input  wire [15:0] cin,
    input  wire [15:0] cout,

    input  wire [7:0]  kernel_size,
    input  wire [7:0]  stride,
    input  wire [7:0]  padding,

    // ============================================================
    // Current Convolution Indices
    //
    // The 4x4 tile maps:
    //   4 output positions along W  x  4 output channels
    //
    // Position lanes:
    //   lane 0 -> (oh, ow_base + 0)
    //   lane 1 -> (oh, ow_base + 1)
    //   lane 2 -> (oh, ow_base + 2)
    //   lane 3 -> (oh, ow_base + 3)
    //
    // Channel lanes:
    //   lane 0 -> oc_base + 0
    //   lane 1 -> oc_base + 1
    //   lane 2 -> oc_base + 2
    //   lane 3 -> oc_base + 3
    // ============================================================
    input  wire [15:0] oh,
    input  wire [15:0] ow_base,
    input  wire [15:0] oc_base,

    input  wire [15:0] ic,
    input  wire [7:0]  kh,
    input  wire [7:0]  kw,

    // ============================================================
    // Output Shape
    // Used to disable lanes at the right edge of the feature map.
    // ============================================================
    input  wire [15:0] out_h,
    input  wire [15:0] out_w,

    // ============================================================
    // Four Activation Addresses
    // ============================================================
    output reg  [INPUT_ADDR_WIDTH-1:0]  input_addr_0,
    output reg  [INPUT_ADDR_WIDTH-1:0]  input_addr_1,
    output reg  [INPUT_ADDR_WIDTH-1:0]  input_addr_2,
    output reg  [INPUT_ADDR_WIDTH-1:0]  input_addr_3,

    // One bit per activation lane.
    // Bit = 0 means zero-padding / invalid output lane.
    output reg  [3:0]                   input_valid_mask,

    // ============================================================
    // Four Weight Addresses
    // ============================================================
    output reg  [WEIGHT_ADDR_WIDTH-1:0] weight_addr_0,
    output reg  [WEIGHT_ADDR_WIDTH-1:0] weight_addr_1,
    output reg  [WEIGHT_ADDR_WIDTH-1:0] weight_addr_2,
    output reg  [WEIGHT_ADDR_WIDTH-1:0] weight_addr_3,

    // One bit per output-channel lane.
    output reg  [3:0]                   weight_valid_mask
);

    // ============================================================
    // Internal arithmetic
    // ============================================================
    integer lane;

    integer current_ow;
    integer in_row;
    integer in_col;

    integer input_index;
    integer kernel_index;
    integer weight_index;

    integer channel_index;

    // ============================================================
    // Combinational Address Generation
    // ============================================================
    always @(*) begin

        // --------------------------------------------------------
        // Safe defaults
        // --------------------------------------------------------
        input_addr_0 = {INPUT_ADDR_WIDTH{1'b0}};
        input_addr_1 = {INPUT_ADDR_WIDTH{1'b0}};
        input_addr_2 = {INPUT_ADDR_WIDTH{1'b0}};
        input_addr_3 = {INPUT_ADDR_WIDTH{1'b0}};

        weight_addr_0 = {WEIGHT_ADDR_WIDTH{1'b0}};
        weight_addr_1 = {WEIGHT_ADDR_WIDTH{1'b0}};
        weight_addr_2 = {WEIGHT_ADDR_WIDTH{1'b0}};
        weight_addr_3 = {WEIGHT_ADDR_WIDTH{1'b0}};

        input_valid_mask  = 4'b0000;
        weight_valid_mask = 4'b0000;

        // Defaults for all temporary variables keep this block purely
        // combinational even when no activation/weight lane is valid.
        current_ow   = 0;
        in_row       = 0;
        in_col       = 0;
        input_index  = 0;
        kernel_index = 0;
        weight_index = 0;
        channel_index = 0;

        // Current kernel element flattened inside one output channel:
        //
        // k = (ic * K * K) + (kh * K) + kw
        kernel_index =
            (ic * kernel_size * kernel_size) +
            (kh * kernel_size) +
            kw;

        // --------------------------------------------------------
        // Activation lanes:
        // four neighboring output positions along output width.
        // --------------------------------------------------------
        for (lane = 0; lane < 4; lane = lane + 1) begin

            current_ow = ow_base + lane;

            // Input coordinate used by this output lane.
            in_row =
                (oh * stride) +
                kh -
                padding;

            in_col =
                (current_ow * stride) +
                kw -
                padding;

            // Lane is valid only when:
            //   1) output coordinate exists
            //   2) current input channel exists
            //   3) kernel coordinate exists
            //   4) translated input coordinate is inside image
            if (
                (oh < out_h) &&
                (current_ow < out_w) &&
                (ic < cin) &&
                (kh < kernel_size) &&
                (kw < kernel_size) &&
                (in_row >= 0) &&
                (in_row < input_h) &&
                (in_col >= 0) &&
                (in_col < input_w)
            ) begin

                input_index =
                    (ic * input_h * input_w) +
                    (in_row * input_w) +
                    in_col;

                case (lane)
                    0: input_addr_0 = input_index[INPUT_ADDR_WIDTH-1:0];
                    1: input_addr_1 = input_index[INPUT_ADDR_WIDTH-1:0];
                    2: input_addr_2 = input_index[INPUT_ADDR_WIDTH-1:0];
                    3: input_addr_3 = input_index[INPUT_ADDR_WIDTH-1:0];
                endcase

                input_valid_mask[lane] = 1'b1;

            end

        end

        // --------------------------------------------------------
        // Weight lanes:
        // four neighboring output channels for the same
        // (ic, kh, kw) kernel element.
        //
        // Weight layout:
        // [COUT][CIN][KH][KW]
        // --------------------------------------------------------
        for (lane = 0; lane < 4; lane = lane + 1) begin

            channel_index = oc_base + lane;

            if (
                (channel_index < cout) &&
                (ic < cin) &&
                (kh < kernel_size) &&
                (kw < kernel_size)
            ) begin

                weight_index =
                    (channel_index * cin * kernel_size * kernel_size) +
                    kernel_index;

                case (lane)
                    0: weight_addr_0 = weight_index[WEIGHT_ADDR_WIDTH-1:0];
                    1: weight_addr_1 = weight_index[WEIGHT_ADDR_WIDTH-1:0];
                    2: weight_addr_2 = weight_index[WEIGHT_ADDR_WIDTH-1:0];
                    3: weight_addr_3 = weight_index[WEIGHT_ADDR_WIDTH-1:0];
                endcase

                weight_valid_mask[lane] = 1'b1;

            end

        end

    end

endmodule
