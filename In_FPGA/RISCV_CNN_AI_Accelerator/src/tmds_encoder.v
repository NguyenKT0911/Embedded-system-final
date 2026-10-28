`timescale 1ns/1ps

// Standard DVI 1.0 / HDMI 8b/10b TMDS Encoder
module tmds_encoder (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data_in,
    input  wire [1:0] c_in,      // Control signals (e.g. HSYNC, VSYNC)
    input  wire       de,        // Data enable (active high during display)
    output reg  [9:0] data_out
);

    wire [3:0] ones_cnt = data_in[0] + data_in[1] + data_in[2] + data_in[3] +
                          data_in[4] + data_in[5] + data_in[6] + data_in[7];

    wire use_xnor = (ones_cnt > 4'd4) || (ones_cnt == 4'd4 && data_in[0] == 1'b0);

    wire [8:0] q_m;
    assign q_m[0] = data_in[0];
    assign q_m[1] = use_xnor ? ~(q_m[0] ^ data_in[1]) : (q_m[0] ^ data_in[1]);
    assign q_m[2] = use_xnor ? ~(q_m[1] ^ data_in[2]) : (q_m[1] ^ data_in[2]);
    assign q_m[3] = use_xnor ? ~(q_m[2] ^ data_in[3]) : (q_m[2] ^ data_in[3]);
    assign q_m[4] = use_xnor ? ~(q_m[3] ^ data_in[4]) : (q_m[3] ^ data_in[4]);
    assign q_m[5] = use_xnor ? ~(q_m[4] ^ data_in[5]) : (q_m[4] ^ data_in[5]);
    assign q_m[6] = use_xnor ? ~(q_m[5] ^ data_in[6]) : (q_m[5] ^ data_in[6]);
    assign q_m[7] = use_xnor ? ~(q_m[6] ^ data_in[7]) : (q_m[6] ^ data_in[7]);
    assign q_m[8] = use_xnor ? 1'b0 : 1'b1;

    wire [3:0] ones_qm = q_m[0] + q_m[1] + q_m[2] + q_m[3] +
                         q_m[4] + q_m[5] + q_m[6] + q_m[7];
    wire [3:0] zeros_qm = 4'd8 - ones_qm;

    // Keep the arithmetic explicitly signed. Unsigned four-bit subtraction
    // wraps on negative values and produces invalid TMDS running disparity.
    wire signed [5:0] symbol_balance =
        $signed({2'b00, ones_qm}) - $signed({2'b00, zeros_qm});
    reg signed [5:0] disparity;

    always @(posedge clk) begin
        if (rst) begin
            disparity <= 6'sd0;
            data_out  <= 10'd0;
        end else if (!de) begin
            disparity <= 6'sd0;
            case (c_in)
                2'b00:   data_out <= 10'b1101010100;
                2'b01:   data_out <= 10'b0010101011;
                2'b10:   data_out <= 10'b0101010100;
                default: data_out <= 10'b1010101011;
            endcase
        end else begin
            if (disparity == 6'sd0 || ones_qm == zeros_qm) begin
                if (q_m[8] == 1'b0) begin
                    data_out <= {2'b10, ~q_m[7:0]};
                    disparity <= disparity - symbol_balance;
                end else begin
                    data_out <= {2'b01, q_m[7:0]};
                    disparity <= disparity + symbol_balance;
                end
            end else begin
                if ((disparity > 0 && ones_qm > zeros_qm) ||
                    (disparity < 0 && zeros_qm > ones_qm)) begin
                    data_out <= {1'b1, q_m[8], ~q_m[7:0]};
                    disparity <= disparity - symbol_balance +
                                 (q_m[8] ? 6'sd2 : 6'sd0);
                end else begin
                    data_out <= {1'b0, q_m[8], q_m[7:0]};
                    disparity <= disparity + symbol_balance -
                                 (q_m[8] ? 6'sd0 : 6'sd2);
                end
            end
        end
    end

endmodule

