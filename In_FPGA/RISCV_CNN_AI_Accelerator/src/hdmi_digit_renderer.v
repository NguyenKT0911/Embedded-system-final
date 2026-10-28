`timescale 1ns/1ps

module hdmi_digit_renderer (
    input  wire        clk_pixel,    // 27.000 MHz (720x480p @ 60Hz CEA-861)
    input  wire        rst,
    input  wire [3:0]  prediction,   // 0..9
    input  wire [6:0]  confidence,   // 0..100 percent
    input  wire        confidence_valid,
    input  wire [6:0]  sample_index, // 0..99, displayed as 001..100
    input  wire [799:0] image_bits,  // 28x28 input image, row-major
    input  wire        image_valid,
    output reg  [7:0]  rgb_r,
    output reg  [7:0]  rgb_g,
    output reg  [7:0]  rgb_b,
    output reg         hsync,
    output reg         vsync,
    output reg         de
);

    // =========================================================================
    // CEA-861 STANDARD TIMING FOR 720x480p @ 59.94/60Hz (27.000 MHz Pixel Clock)
    // =========================================================================
    localparam H_ACTIVE = 720;
    localparam H_FRONT  = 16;
    localparam H_SYNC   = 62;
    localparam H_BACK   = 60;
    localparam H_TOTAL  = H_ACTIVE + H_FRONT + H_SYNC + H_BACK; // 858

    localparam V_ACTIVE = 480;
    localparam V_FRONT  = 9;
    localparam V_SYNC   = 6;
    localparam V_BACK   = 30;
    localparam V_TOTAL  = V_ACTIVE + V_FRONT + V_SYNC + V_BACK; // 525

    reg [10:0] h_cnt;
    reg [9:0]  v_cnt;

    always @(posedge clk_pixel) begin
        if (rst) begin
            h_cnt <= 11'd0;
            v_cnt <= 10'd0;
        end else begin
            if (h_cnt == H_TOTAL - 1) begin
                h_cnt <= 11'd0;
                if (v_cnt == V_TOTAL - 1)
                    v_cnt <= 10'd0;
                else
                    v_cnt <= v_cnt + 10'd1;
            end else begin
                h_cnt <= h_cnt + 11'd1;
            end
        end
    end

    wire [10:0] x = h_cnt;
    wire [9:0]  y = v_cnt;

    wire active_area = (x < H_ACTIVE) && (y < V_ACTIVE);
    // Active-low sync pulses matching CEA-861 standard
    wire hsync_int = ~((x >= H_ACTIVE + H_FRONT) && (x < H_ACTIVE + H_FRONT + H_SYNC));
    wire vsync_int = ~((y >= V_ACTIVE + V_FRONT) && (y < V_ACTIVE + V_FRONT + V_SYNC));

    // =========================================================================
    // BITMAP FONT FOR DIGITS 0 TO 9 (12x16 pixel matrix per digit)
    // =========================================================================
    function [11:0] get_digit_row;
        input [3:0] digit;
        input [3:0] row;
        begin
            case (digit)
                4'd0: case (row)
                    4'd0:  get_digit_row = 12'b001111111100;
                    4'd1:  get_digit_row = 12'b011111111110;
                    4'd2:  get_digit_row = 12'b111000000111;
                    4'd3:  get_digit_row = 12'b111000000111;
                    4'd4:  get_digit_row = 12'b111000000111;
                    4'd5:  get_digit_row = 12'b111000000111;
                    4'd6:  get_digit_row = 12'b111000000111;
                    4'd7:  get_digit_row = 12'b111000000111;
                    4'd8:  get_digit_row = 12'b111000000111;
                    4'd9:  get_digit_row = 12'b111000000111;
                    4'd10: get_digit_row = 12'b111000000111;
                    4'd11: get_digit_row = 12'b111000000111;
                    4'd12: get_digit_row = 12'b111000000111;
                    4'd13: get_digit_row = 12'b111000000111;
                    4'd14: get_digit_row = 12'b011111111110;
                    4'd15: get_digit_row = 12'b001111111100;
                endcase
                4'd1: case (row)
                    4'd0:  get_digit_row = 12'b000001110000;
                    4'd1:  get_digit_row = 12'b000011110000;
                    4'd2:  get_digit_row = 12'b000111110000;
                    4'd3:  get_digit_row = 12'b001101110000;
                    4'd4:  get_digit_row = 12'b000001110000;
                    4'd5:  get_digit_row = 12'b000001110000;
                    4'd6:  get_digit_row = 12'b000001110000;
                    4'd7:  get_digit_row = 12'b000001110000;
                    4'd8:  get_digit_row = 12'b000001110000;
                    4'd9:  get_digit_row = 12'b000001110000;
                    4'd10: get_digit_row = 12'b000001110000;
                    4'd11: get_digit_row = 12'b000001110000;
                    4'd12: get_digit_row = 12'b000001110000;
                    4'd13: get_digit_row = 12'b000001110000;
                    4'd14: get_digit_row = 12'b011111111110;
                    4'd15: get_digit_row = 12'b011111111110;
                endcase
                4'd2: case (row)
                    4'd0:  get_digit_row = 12'b001111111100;
                    4'd1:  get_digit_row = 12'b011111111110;
                    4'd2:  get_digit_row = 12'b111000000111;
                    4'd3:  get_digit_row = 12'b111000000111;
                    4'd4:  get_digit_row = 12'b000000000111;
                    4'd5:  get_digit_row = 12'b000000001110;
                    4'd6:  get_digit_row = 12'b000000011100;
                    4'd7:  get_digit_row = 12'b000000111000;
                    4'd8:  get_digit_row = 12'b000001110000;
                    4'd9:  get_digit_row = 12'b000011100000;
                    4'd10: get_digit_row = 12'b000111000000;
                    4'd11: get_digit_row = 12'b001110000000;
                    4'd12: get_digit_row = 12'b011100000000;
                    4'd13: get_digit_row = 12'b111000000000;
                    4'd14: get_digit_row = 12'b111111111111;
                    4'd15: get_digit_row = 12'b111111111111;
                endcase
                4'd3: case (row)
                    4'd0:  get_digit_row = 12'b001111111100;
                    4'd1:  get_digit_row = 12'b011111111110;
                    4'd2:  get_digit_row = 12'b111000000111;
                    4'd3:  get_digit_row = 12'b000000000111;
                    4'd4:  get_digit_row = 12'b000000000111;
                    4'd5:  get_digit_row = 12'b000000000111;
                    4'd6:  get_digit_row = 12'b000000011110;
                    4'd7:  get_digit_row = 12'b000111111100;
                    4'd8:  get_digit_row = 12'b000000011110;
                    4'd9:  get_digit_row = 12'b000000000111;
                    4'd10: get_digit_row = 12'b000000000111;
                    4'd11: get_digit_row = 12'b000000000111;
                    4'd12: get_digit_row = 12'b111000000111;
                    4'd13: get_digit_row = 12'b111000000111;
                    4'd14: get_digit_row = 12'b011111111110;
                    4'd15: get_digit_row = 12'b001111111100;
                endcase
                4'd4: case (row)
                    4'd0:  get_digit_row = 12'b000000011100;
                    4'd1:  get_digit_row = 12'b000000111100;
                    4'd2:  get_digit_row = 12'b000001101100;
                    4'd3:  get_digit_row = 12'b000011001100;
                    4'd4:  get_digit_row = 12'b000110001100;
                    4'd5:  get_digit_row = 12'b001100001100;
                    4'd6:  get_digit_row = 12'b011000001100;
                    4'd7:  get_digit_row = 12'b110000001100;
                    4'd8:  get_digit_row = 12'b111111111111;
                    4'd9:  get_digit_row = 12'b111111111111;
                    4'd10: get_digit_row = 12'b000000001100;
                    4'd11: get_digit_row = 12'b000000001100;
                    4'd12: get_digit_row = 12'b000000001100;
                    4'd13: get_digit_row = 12'b000000001100;
                    4'd14: get_digit_row = 12'b000000001100;
                    4'd15: get_digit_row = 12'b000000001100;
                endcase
                4'd5: case (row)
                    4'd0:  get_digit_row = 12'b111111111111;
                    4'd1:  get_digit_row = 12'b111111111111;
                    4'd2:  get_digit_row = 12'b111000000000;
                    4'd3:  get_digit_row = 12'b111000000000;
                    4'd4:  get_digit_row = 12'b111000000000;
                    4'd5:  get_digit_row = 12'b111111111000;
                    4'd6:  get_digit_row = 12'b111111111110;
                    4'd7:  get_digit_row = 12'b000000000111;
                    4'd8:  get_digit_row = 12'b000000000111;
                    4'd9:  get_digit_row = 12'b000000000111;
                    4'd10: get_digit_row = 12'b000000000111;
                    4'd11: get_digit_row = 12'b000000000111;
                    4'd12: get_digit_row = 12'b111000000111;
                    4'd13: get_digit_row = 12'b111000000111;
                    4'd14: get_digit_row = 12'b011111111110;
                    4'd15: get_digit_row = 12'b001111111100;
                endcase
                4'd6: case (row)
                    4'd0:  get_digit_row = 12'b001111111100;
                    4'd1:  get_digit_row = 12'b011111111110;
                    4'd2:  get_digit_row = 12'b111000000000;
                    4'd3:  get_digit_row = 12'b111000000000;
                    4'd4:  get_digit_row = 12'b111000000000;
                    4'd5:  get_digit_row = 12'b111000000000;
                    4'd6:  get_digit_row = 12'b111111111100;
                    4'd7:  get_digit_row = 12'b111111111110;
                    4'd8:  get_digit_row = 12'b111000000111;
                    4'd9:  get_digit_row = 12'b111000000111;
                    4'd10: get_digit_row = 12'b111000000111;
                    4'd11: get_digit_row = 12'b111000000111;
                    4'd12: get_digit_row = 12'b111000000111;
                    4'd13: get_digit_row = 12'b111000000111;
                    4'd14: get_digit_row = 12'b011111111110;
                    4'd15: get_digit_row = 12'b001111111100;
                endcase
                4'd7: case (row)
                    4'd0:  get_digit_row = 12'b111111111111;
                    4'd1:  get_digit_row = 12'b111111111111;
                    4'd2:  get_digit_row = 12'b000000000111;
                    4'd3:  get_digit_row = 12'b000000000111;
                    4'd4:  get_digit_row = 12'b000000001110;
                    4'd5:  get_digit_row = 12'b000000011100;
                    4'd6:  get_digit_row = 12'b000000111000;
                    4'd7:  get_digit_row = 12'b000001110000;
                    4'd8:  get_digit_row = 12'b000011100000;
                    4'd9:  get_digit_row = 12'b000111000000;
                    4'd10: get_digit_row = 12'b001110000000;
                    4'd11: get_digit_row = 12'b001110000000;
                    4'd12: get_digit_row = 12'b001110000000;
                    4'd13: get_digit_row = 12'b001110000000;
                    4'd14: get_digit_row = 12'b001110000000;
                    4'd15: get_digit_row = 12'b001110000000;
                endcase
                4'd8: case (row)
                    4'd0:  get_digit_row = 12'b001111111100;
                    4'd1:  get_digit_row = 12'b011111111110;
                    4'd2:  get_digit_row = 12'b111000000111;
                    4'd3:  get_digit_row = 12'b111000000111;
                    4'd4:  get_digit_row = 12'b111000000111;
                    4'd5:  get_digit_row = 12'b011111111110;
                    4'd6:  get_digit_row = 12'b001111111100;
                    4'd7:  get_digit_row = 12'b011111111110;
                    4'd8:  get_digit_row = 12'b111000000111;
                    4'd9:  get_digit_row = 12'b111000000111;
                    4'd10: get_digit_row = 12'b111000000111;
                    4'd11: get_digit_row = 12'b111000000111;
                    4'd12: get_digit_row = 12'b111000000111;
                    4'd13: get_digit_row = 12'b111000000111;
                    4'd14: get_digit_row = 12'b011111111110;
                    4'd15: get_digit_row = 12'b001111111100;
                endcase
                4'd9: case (row)
                    4'd0:  get_digit_row = 12'b001111111100;
                    4'd1:  get_digit_row = 12'b011111111110;
                    4'd2:  get_digit_row = 12'b111000000111;
                    4'd3:  get_digit_row = 12'b111000000111;
                    4'd4:  get_digit_row = 12'b111000000111;
                    4'd5:  get_digit_row = 12'b111000000111;
                    4'd6:  get_digit_row = 12'b011111111111;
                    4'd7:  get_digit_row = 12'b001111111111;
                    4'd8:  get_digit_row = 12'b000000000111;
                    4'd9:  get_digit_row = 12'b000000000111;
                    4'd10: get_digit_row = 12'b000000000111;
                    4'd11: get_digit_row = 12'b000000000111;
                    4'd12: get_digit_row = 12'b111000000111;
                    4'd13: get_digit_row = 12'b111000000111;
                    4'd14: get_digit_row = 12'b011111111110;
                    4'd15: get_digit_row = 12'b001111111100;
                endcase
                default: get_digit_row = 12'd0;
            endcase
        end
    endfunction

    // =========================================================================
    // GRAPHICS GENERATION ON 720x480 CANVAS
    // Left: the real 28x28 sample read from SD. Right: the CNN prediction.
    // Header: sample number 001..100. Bottom: confidence percentage.
    // =========================================================================
    wire in_image = (x >= 11'd50) && (x < 11'd330) &&
                    (y >= 10'd90) && (y < 10'd370);
    wire [10:0] image_col_full = (x - 11'd50) / 11'd10;
    wire [9:0] image_row_full = (y - 10'd90) / 10'd10;
    wire [5:0] image_col = image_col_full[5:0];
    wire [5:0] image_row = image_row_full[5:0];
    wire [9:0] image_pixel_index = image_row * 10'd28 + image_col;
    wire image_pixel = image_valid && in_image &&
                       image_bits[image_pixel_index];

    wire in_digit_box = (x >= 11'd480) && (x < 11'd600) &&
                        (y >= 10'd130) && (y < 10'd322);
    wire [10:0] digit_col_scaled = (x - 11'd480) / 11'd10;
    wire [9:0]  digit_row_scaled = (y - 10'd130) / 10'd12;
    wire [3:0] digit_col_idx = digit_col_scaled[3:0];
    wire [3:0] digit_row_idx = digit_row_scaled[3:0];
    wire [11:0] current_row_bits = get_digit_row(prediction, digit_row_idx);
    wire digit_pixel = confidence_valid && in_digit_box &&
                       current_row_bits[11 - digit_col_idx];

    // Sample number (human-friendly 001..100) in the top banner.
    wire [7:0] sample_number = {1'b0, sample_index} + 8'd1;
    wire [3:0] sample_hundreds = (sample_number == 8'd100) ? 4'd1 : 4'd0;
    wire [7:0] sample_tens_full = (sample_number == 8'd100)
                                ? 8'd0 : (sample_number / 8'd10);
    wire [7:0] sample_ones_full = (sample_number == 8'd100)
                                ? 8'd0 : (sample_number % 8'd10);
    wire [3:0] sample_tens = sample_tens_full[3:0];
    wire [3:0] sample_ones = sample_ones_full[3:0];
    wire in_sample_y = (y >= 10'd18) && (y < 10'd50);
    wire [9:0] sample_row_full = ((y - 10'd18) >> 1);
    wire [3:0] sample_row = sample_row_full[3:0];
    wire [11:0] sample_h_row = get_digit_row(sample_hundreds, sample_row);
    wire [11:0] sample_t_row = get_digit_row(sample_tens, sample_row);
    wire [11:0] sample_o_row = get_digit_row(sample_ones, sample_row);
    wire in_sample_h = in_sample_y && (x >= 11'd150) && (x < 11'd174);
    wire in_sample_t = in_sample_y && (x >= 11'd178) && (x < 11'd202);
    wire in_sample_o = in_sample_y && (x >= 11'd206) && (x < 11'd230);
    wire [10:0] sample_h_col_full = ((x - 11'd150) >> 1);
    wire [10:0] sample_t_col_full = ((x - 11'd178) >> 1);
    wire [10:0] sample_o_col_full = ((x - 11'd206) >> 1);
    wire [3:0] sample_h_col = sample_h_col_full[3:0];
    wire [3:0] sample_t_col = sample_t_col_full[3:0];
    wire [3:0] sample_o_col = sample_o_col_full[3:0];
    wire sample_digit_pixel =
        (in_sample_h && sample_h_row[11 - sample_h_col]) ||
        (in_sample_t && sample_t_row[11 - sample_t_col]) ||
        (in_sample_o && sample_o_row[11 - sample_o_col]);

    // Minimal block labels: IMG over the input and AI over the prediction.
    wire label_img_pixel =
        // I
        (((y >= 10'd20 && y < 10'd24) || (y >= 10'd44 && y < 10'd48)) &&
          x >= 11'd58 && x < 11'd78) ||
        (x >= 11'd66 && x < 11'd70 && y >= 10'd20 && y < 10'd48) ||
        // M
        ((x >= 11'd86 && x < 11'd90 || x >= 11'd102 && x < 11'd106) &&
          y >= 10'd20 && y < 10'd48) ||
        ((x >= 11'd90 && x < 11'd94 || x >= 11'd98 && x < 11'd102) &&
          y >= 10'd24 && y < 10'd32) ||
        (x >= 11'd94 && x < 11'd98 && y >= 10'd28 && y < 10'd36) ||
        // G
        ((x >= 11'd114 && x < 11'd134) &&
         ((y >= 10'd20 && y < 10'd24) || (y >= 10'd44 && y < 10'd48))) ||
        (x >= 11'd114 && x < 11'd118 && y >= 10'd20 && y < 10'd48) ||
        (x >= 11'd126 && x < 11'd134 && y >= 10'd32 && y < 10'd36) ||
        (x >= 11'd130 && x < 11'd134 && y >= 10'd32 && y < 10'd48);
    wire label_ai_pixel =
        // A
        ((x >= 11'd444 && x < 11'd464) &&
         ((y >= 10'd20 && y < 10'd24) || (y >= 10'd32 && y < 10'd36))) ||
        ((x >= 11'd444 && x < 11'd448 || x >= 11'd460 && x < 11'd464) &&
          y >= 10'd20 && y < 10'd48) ||
        // I
        (((y >= 10'd20 && y < 10'd24) || (y >= 10'd44 && y < 10'd48)) &&
          x >= 11'd472 && x < 11'd492) ||
        (x >= 11'd480 && x < 11'd484 && y >= 10'd20 && y < 10'd48);

    wire [6:0] confidence_clamped = (confidence > 7'd100) ? 7'd100 : confidence;
    wire [3:0] confidence_hundreds = (confidence_clamped == 7'd100) ? 4'd1 : 4'd0;
    wire [6:0] confidence_tens_full = (confidence_clamped == 7'd100)
                                    ? 7'd0 : (confidence_clamped / 7'd10);
    wire [6:0] confidence_ones_full = (confidence_clamped == 7'd100)
                                    ? 7'd0 : (confidence_clamped % 7'd10);
    wire [3:0] confidence_tens = confidence_tens_full[3:0];
    wire [3:0] confidence_ones = confidence_ones_full[3:0];
    wire in_conf_y = (y >= 10'd408) && (y < 10'd440);
    wire [9:0] conf_row_full = ((y - 10'd408) >> 1);
    wire [3:0] conf_row = conf_row_full[3:0];
    wire [11:0] conf_h_row = get_digit_row(confidence_hundreds, conf_row);
    wire [11:0] conf_t_row = get_digit_row(confidence_tens, conf_row);
    wire [11:0] conf_o_row = get_digit_row(confidence_ones, conf_row);
    wire in_conf_h = in_conf_y && (x >= 11'd294) && (x < 11'd318);
    wire in_conf_t = in_conf_y && (x >= 11'd322) && (x < 11'd346);
    wire in_conf_o = in_conf_y && (x >= 11'd350) && (x < 11'd374);
    wire [10:0] conf_h_col_full = ((x - 11'd294) >> 1);
    wire [10:0] conf_t_col_full = ((x - 11'd322) >> 1);
    wire [10:0] conf_o_col_full = ((x - 11'd350) >> 1);
    wire [3:0] conf_h_col = conf_h_col_full[3:0];
    wire [3:0] conf_t_col = conf_t_col_full[3:0];
    wire [3:0] conf_o_col = conf_o_col_full[3:0];
    wire conf_digit_pixel = confidence_valid && (
        (in_conf_h && conf_h_row[11 - conf_h_col]) ||
        (in_conf_t && conf_t_row[11 - conf_t_col]) ||
        (in_conf_o && conf_o_row[11 - conf_o_col]));

    wire in_percent = confidence_valid && in_conf_y &&
                      (x >= 11'd382) && (x < 11'd406);
    wire [10:0] percent_x_full = x - 11'd382;
    wire [9:0] percent_y_full = y - 10'd408;
    wire [4:0] percent_x = percent_x_full[4:0];
    wire [5:0] percent_y = percent_y_full[5:0];
    wire percent_pixel = in_percent && (
        ((percent_x < 5'd8) && (percent_y < 6'd8) &&
         ((percent_x < 5'd2) || (percent_x >= 5'd6) ||
          (percent_y < 6'd2) || (percent_y >= 6'd6))) ||
        ((percent_x >= 5'd16) && (percent_y >= 6'd24) &&
         ((percent_x < 5'd18) || (percent_x >= 5'd22) ||
          (percent_y < 6'd26) || (percent_y >= 6'd30))) ||
        ((percent_x + percent_y >= 6'd22) &&
         (percent_x + percent_y <= 6'd26)));

    wire input_border =
        (((x >= 11'd38 && x <= 11'd40) || (x >= 11'd340 && x <= 11'd342)) &&
         (y >= 10'd78 && y <= 10'd382)) ||
        (((y >= 10'd78 && y <= 10'd80) || (y >= 10'd380 && y <= 10'd382)) &&
         (x >= 11'd38 && x <= 11'd342));
    wire result_border =
        (((x >= 11'd398 && x <= 11'd400) || (x >= 11'd678 && x <= 11'd680)) &&
         (y >= 10'd78 && y <= 10'd382)) ||
        (((y >= 10'd78 && y <= 10'd80) || (y >= 10'd380 && y <= 10'd382)) &&
         (x >= 11'd398 && x <= 11'd680));
    wire in_input_area = x > 11'd40 && x < 11'd340 && y > 10'd80 && y < 10'd380;
    wire in_result_area = x > 11'd400 && x < 11'd678 && y > 10'd80 && y < 10'd380;
    wire arrow_pixel = ((x >= 11'd354 && x < 11'd386) &&
                        (y >= 10'd226 && y < 10'd232)) ||
                       ((x >= 11'd378 && x < 11'd390) &&
                        (y >= (10'd220 + (x - 11'd378)) &&
                         y <  (10'd238 - (x - 11'd378))));
    wire in_header_bar = (y >= 10'd10 && y <= 10'd60) &&
                         (x >= 11'd38 && x <= 11'd680);
    wire in_status_bar = (y >= 10'd400 && y <= 10'd450) &&
                         (x >= 11'd90 && x <= 11'd630);

    always @(posedge clk_pixel) begin
        if (rst || !active_area) begin
            rgb_r <= 8'h00; rgb_g <= 8'h00; rgb_b <= 8'h00; de <= 1'b0;
        end else begin
            de <= 1'b1;
            if (image_pixel) begin
                rgb_r <= 8'hF0; rgb_g <= 8'hF8; rgb_b <= 8'hFF;
            end else if (digit_pixel) begin
                rgb_r <= 8'h00; rgb_g <= 8'hFF; rgb_b <= 8'h80;
            end else if (conf_digit_pixel || percent_pixel) begin
                rgb_r <= 8'hFF; rgb_g <= 8'hD0; rgb_b <= 8'h20;
            end else if (sample_digit_pixel || label_img_pixel || label_ai_pixel) begin
                rgb_r <= 8'h60; rgb_g <= 8'hF0; rgb_b <= 8'hFF;
            end else if (arrow_pixel || input_border || result_border) begin
                rgb_r <= 8'h00; rgb_g <= 8'hE0; rgb_b <= 8'hFF;
            end else if (in_header_bar) begin
                rgb_r <= 8'h10; rgb_g <= 8'h20; rgb_b <= 8'h50;
            end else if (in_status_bar) begin
                rgb_r <= 8'h10; rgb_g <= 8'h50; rgb_b <= 8'h25;
            end else if (in_input_area || in_result_area) begin
                rgb_r <= 8'h0A; rgb_g <= 8'h12; rgb_b <= 8'h24;
            end else if ((x[4:0] == 5'd0) || (y[4:0] == 5'd0)) begin
                rgb_r <= 8'h05; rgb_g <= 8'h0D; rgb_b <= 8'h1A;
            end else begin
                rgb_r <= 8'h02; rgb_g <= 8'h05; rgb_b <= 8'h0E;
            end
        end
        hsync <= hsync_int;
        vsync <= vsync_int;
    end

endmodule

