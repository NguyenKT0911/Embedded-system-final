`timescale 1ns/1ps

module accelerator_mmio #(
    parameter [31:0] BASE_ADDR = 32'h4000_0000
)(
    // Clock and Reset
    input  wire         clk,
    input  wire         rst,

    // RISC-V MMIO Interface
    input  wire [31:0]  mmio_addr,
    input  wire [31:0]  mmio_wdata,
    input  wire         mmio_we,
    input  wire         mmio_re,

    output reg  [31:0]  mmio_rdata,
    output wire         mmio_hit,

    // Control Outputs to Accelerator Core
    output reg          start_pulse,
    output reg          clear_pulse,

    // Configuration Registers
    output reg  [15:0]  input_h,
    output reg  [15:0]  input_w,
    output reg  [15:0]  cin,
    output reg  [15:0]  cout,
    output reg  [7:0]   kernel_size,
    output reg  [7:0]   stride,
    output reg  [7:0]   padding,
    output reg          relu_en,
    output wire [31:0] input_count_value,
    output wire [31:0] weight_count_value,

    // Input Activation Interface
    output reg  [31:0]  input_data_word,
    output reg          input_data_valid,

    // Weight Interface
    output reg  [31:0]  weight_data_word,
    output reg          weight_data_valid,

    // Output Interface
    input  wire [31:0]  core_output_data,
    input  wire [31:0]  core_output_count,
    output reg          output_read_pulse,

    // Accelerator Core Status
    input  wire         core_busy,
    input  wire         core_done,
    input  wire         core_error,
    input  wire [31:0]  core_error_code
);

    // Register Offsets
    localparam [7:0] ADDR_CTRL         = 8'h00;
    localparam [7:0] ADDR_STATUS       = 8'h04;

    localparam [7:0] ADDR_INPUT_H      = 8'h08;
    localparam [7:0] ADDR_INPUT_W      = 8'h0C;

    localparam [7:0] ADDR_CIN          = 8'h10;
    localparam [7:0] ADDR_COUT         = 8'h14;

    localparam [7:0] ADDR_KERNEL_SIZE  = 8'h18;
    localparam [7:0] ADDR_STRIDE       = 8'h1C;
    localparam [7:0] ADDR_PADDING      = 8'h20;
    localparam [7:0] ADDR_RELU_EN      = 8'h24;

    localparam [7:0] ADDR_OUT_H        = 8'h28;
    localparam [7:0] ADDR_OUT_W        = 8'h2C;

    localparam [7:0] ADDR_INPUT_DATA   = 8'h30;
    localparam [7:0] ADDR_WEIGHT_DATA  = 8'h34;
    localparam [7:0] ADDR_OUTPUT_DATA  = 8'h38;

    localparam [7:0] ADDR_INPUT_COUNT  = 8'h3C;
    localparam [7:0] ADDR_WEIGHT_COUNT = 8'h40;
    localparam [7:0] ADDR_OUTPUT_COUNT = 8'h44;

    localparam [7:0] ADDR_ERROR_CODE   = 8'h48;

    // Address Decode
    wire [31:0] addr_offset_full;
    wire [7:0]  addr_offset;

    assign addr_offset_full = mmio_addr - BASE_ADDR;
    assign addr_offset      = addr_offset_full[7:0];

    // Hit only the defined, word-aligned register window 0x00..0x48.
    assign mmio_hit =
        (mmio_addr >= BASE_ADDR) &&
        (mmio_addr <= (BASE_ADDR + 32'h0000_0048)) &&
        (addr_offset_full[1:0] == 2'b00);

    // Internal Registers
    reg [31:0] input_count;
    reg [31:0] weight_count;

    assign input_count_value  = input_count;
    assign weight_count_value = weight_count;

    reg        done_reg;
    reg        error_reg;
    reg [31:0] error_code_reg;

    // Output Dimension Calculation
    // Hout = floor((Hin + 2P - K) / S) + 1
    // Wout = floor((Win + 2P - K) / S) + 1
    // Version 0.1 later validates K=3, S=1, P=1 in the controller.
    wire [16:0] padded_h;
    wire [16:0] padded_w;
    wire [16:0] kernel_ext;
    wire [16:0] out_h_full;
    wire [16:0] out_w_full;
    wire [15:0] out_h;
    wire [15:0] out_w;

    assign padded_h   = {1'b0, input_h} + ({9'd0, padding} << 1);
    assign padded_w   = {1'b0, input_w} + ({9'd0, padding} << 1);
    assign kernel_ext = {9'd0, kernel_size};

    assign out_h_full =
        ((stride != 8'd0) && (padded_h >= kernel_ext))
        ? (((padded_h - kernel_ext) / stride) + 17'd1)
        : 17'd0;

    assign out_w_full =
        ((stride != 8'd0) && (padded_w >= kernel_ext))
        ? (((padded_w - kernel_ext) / stride) + 17'd1)
        : 17'd0;

    // Configuration registers limit dimensions to 16 bits.  Make the
    // intended truncation explicit so synthesis does not report a width
    // mismatch on the arithmetic expression.
    assign out_h = out_h_full[15:0];
    assign out_w = out_w_full[15:0];

    // Sequential Logic: MMIO Writes, Pulses, and Latched Status
    always @(posedge clk) begin
        if (rst) begin
            // Control pulses
            start_pulse       <= 1'b0;
            clear_pulse       <= 1'b0;

            // Configuration registers
            input_h           <= 16'd0;
            input_w           <= 16'd0;
            cin               <= 16'd0;
            cout              <= 16'd0;
            kernel_size       <= 8'd0;
            stride            <= 8'd0;
            padding           <= 8'd0;
            relu_en           <= 1'b0;

            // Input interface
            input_data_word   <= 32'd0;
            input_data_valid  <= 1'b0;

            // Weight interface
            weight_data_word  <= 32'd0;
            weight_data_valid <= 1'b0;

            // Output interface
            output_read_pulse <= 1'b0;

            // Counters
            input_count       <= 32'd0;
            weight_count      <= 32'd0;

            // Latched status
            done_reg          <= 1'b0;
            error_reg         <= 1'b0;
            error_code_reg    <= 32'd0;
        end
        else begin
            // Default values for one-clock pulses
            start_pulse       <= 1'b0;
            clear_pulse       <= 1'b0;
            input_data_valid  <= 1'b0;
            weight_data_valid <= 1'b0;
            output_read_pulse <= 1'b0;

            // Capture status from accelerator core.
            //
            // CLEAR hold-off:
            // clear_pulse is registered.  On the cycle after software
            // writes CTRL.CLEAR, the compute side may still present the
            // previous transaction's DONE/ERROR until that same edge
            // clears its state.  While clear_pulse is high, keep the
            // latched MMIO status cleared and do not re-latch stale status.
            if (clear_pulse) begin
                done_reg       <= 1'b0;
                error_reg      <= 1'b0;
                error_code_reg <= 32'd0;
            end
            else begin
                if (core_done) begin
                    done_reg <= 1'b1;
                end

                if (core_error) begin
                    error_reg      <= 1'b1;
                    error_code_reg <= core_error_code;
                    done_reg       <= 1'b0;
                end
            end

            // MMIO Write
            if (mmio_hit && mmio_we) begin
                case (addr_offset)
                    // CTRL
                    ADDR_CTRL: begin
                        // CLEAR has priority over START.
                        if (mmio_wdata[1] && !core_busy) begin
                            clear_pulse    <= 1'b1;
                            done_reg       <= 1'b0;
                            error_reg      <= 1'b0;
                            error_code_reg <= 32'd0;
                            input_count    <= 32'd0;
                            weight_count   <= 32'd0;
                        end
                        else if (mmio_wdata[0] && !core_busy) begin
                            start_pulse <= 1'b1;
                        end
                    end

                    // Configuration registers
                    ADDR_INPUT_H: begin
                        if (!core_busy)
                            input_h <= mmio_wdata[15:0];
                    end

                    ADDR_INPUT_W: begin
                        if (!core_busy)
                            input_w <= mmio_wdata[15:0];
                    end

                    ADDR_CIN: begin
                        if (!core_busy)
                            cin <= mmio_wdata[15:0];
                    end

                    ADDR_COUT: begin
                        if (!core_busy)
                            cout <= mmio_wdata[15:0];
                    end

                    ADDR_KERNEL_SIZE: begin
                        if (!core_busy)
                            kernel_size <= mmio_wdata[7:0];
                    end

                    ADDR_STRIDE: begin
                        if (!core_busy)
                            stride <= mmio_wdata[7:0];
                    end

                    ADDR_PADDING: begin
                        if (!core_busy)
                            padding <= mmio_wdata[7:0];
                    end

                    ADDR_RELU_EN: begin
                        if (!core_busy)
                            relu_en <= mmio_wdata[0];
                    end

                    // Input activation data
                    ADDR_INPUT_DATA: begin
                        if (!core_busy) begin
                            input_data_word  <= mmio_wdata;
                            input_data_valid <= 1'b1;
                            input_count      <= input_count + 32'd4;
                        end
                    end

                    // Weight data
                    ADDR_WEIGHT_DATA: begin
                        if (!core_busy) begin
                            weight_data_word  <= mmio_wdata;
                            weight_data_valid <= 1'b1;
                            weight_count      <= weight_count + 32'd4;
                        end
                    end

                    default: begin
                        // No action for unsupported write addresses.
                    end
                endcase
            end

            // MMIO Read Side Effects
            if (mmio_hit && mmio_re) begin
                case (addr_offset)
                    ADDR_OUTPUT_DATA: begin
                        if (done_reg && !core_busy)
                            output_read_pulse <= 1'b1;
                    end

                    default: begin
                        // No read side effect.
                    end
                endcase
            end
        end
    end

    // Combinational MMIO Read Logic
    always @(*) begin
        mmio_rdata = 32'd0;

        if (mmio_hit && mmio_re) begin
            case (addr_offset)
                // STATUS: bit2=ERROR, bit1=DONE, bit0=BUSY
                ADDR_STATUS: begin
                    mmio_rdata = {
                        29'd0,
                        error_reg,
                        done_reg,
                        core_busy
                    };
                end

                // Configuration registers
                ADDR_INPUT_H: begin
                    mmio_rdata = {16'd0, input_h};
                end

                ADDR_INPUT_W: begin
                    mmio_rdata = {16'd0, input_w};
                end

                ADDR_CIN: begin
                    mmio_rdata = {16'd0, cin};
                end

                ADDR_COUT: begin
                    mmio_rdata = {16'd0, cout};
                end

                ADDR_KERNEL_SIZE: begin
                    mmio_rdata = {24'd0, kernel_size};
                end

                ADDR_STRIDE: begin
                    mmio_rdata = {24'd0, stride};
                end

                ADDR_PADDING: begin
                    mmio_rdata = {24'd0, padding};
                end

                ADDR_RELU_EN: begin
                    mmio_rdata = {31'd0, relu_en};
                end

                // Calculated output dimensions
                ADDR_OUT_H: begin
                    mmio_rdata = {16'd0, out_h};
                end

                ADDR_OUT_W: begin
                    mmio_rdata = {16'd0, out_w};
                end

                // Output data
                ADDR_OUTPUT_DATA: begin
                    if (done_reg && !core_busy)
                        mmio_rdata = core_output_data;
                    else
                        mmio_rdata = 32'd0;
                end

                // Counters
                ADDR_INPUT_COUNT: begin
                    mmio_rdata = input_count;
                end

                ADDR_WEIGHT_COUNT: begin
                    mmio_rdata = weight_count;
                end

                ADDR_OUTPUT_COUNT: begin
                    mmio_rdata = core_output_count;
                end

                // Error code
                ADDR_ERROR_CODE: begin
                    mmio_rdata = error_code_reg;
                end

                default: begin
                    mmio_rdata = 32'd0;
                end
            endcase
        end
    end

endmodule
