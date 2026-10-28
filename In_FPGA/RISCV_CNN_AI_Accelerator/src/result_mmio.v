`timescale 1ns/1ps

// Small, register-only handoff between the software inference pipeline and
// the display subsystem.  No HDMI timing or video logic is implemented here.
//
// Address map relative to BASE_ADDR:
//   +0x00 PREDICTION  (RW, low 4 bits)
//   +0x04 SAMPLE_ID   (RW)
//   +0x08 CONTROL     (W: bit0 emits a commit pulse, bit1 clears)
//   +0x0c STATUS      (R: bit0 commit pulse, bits7:4 prediction)
module result_mmio #(
    parameter [31:0] BASE_ADDR = 32'h1000_0000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] bus_addr,
    input  wire [31:0] bus_wdata,
    input  wire        bus_re,
    input  wire        bus_we,
    output reg  [31:0] bus_rdata,
    output wire        bus_hit,
    output reg  [3:0]  prediction,
    output reg  [31:0] sample_id,
    output reg         prediction_valid
);
    assign bus_hit = (bus_addr >= BASE_ADDR) &&
                     (bus_addr <= (BASE_ADDR + 32'h0000_000c));

    always @(*) begin
        bus_rdata = 32'd0;
        if (bus_re && bus_hit) begin
            case (bus_addr[3:0])
                4'h0: bus_rdata = {28'd0, prediction};
                4'h4: bus_rdata = sample_id;
                4'hc: bus_rdata = {24'd0, prediction, 3'd0, prediction_valid};
                default: bus_rdata = 32'd0;
            endcase
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            prediction       <= 4'd0;
            sample_id        <= 32'd0;
            prediction_valid <= 1'b0;
        end else begin
            // A one-cycle pulse is safe to cross into the faster 27 MHz
            // display domain and reports every commit, even repeated digits.
            prediction_valid <= 1'b0;
            if (bus_we && bus_hit) begin
                case (bus_addr[3:0])
                    4'h0: prediction <= bus_wdata[3:0];
                    4'h4: sample_id  <= bus_wdata;
                    4'h8: begin
                        if (bus_wdata[0] && !bus_wdata[1])
                            prediction_valid <= 1'b1;
                    end
                    default: begin end
                endcase
            end
        end
    end
endmodule
