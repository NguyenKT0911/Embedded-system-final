`timescale 1ns/1ps

module tb_accelerator_control_top;

    // Base Address / Register Map
    localparam [31:0] BASE_ADDR       = 32'h4000_0000;

    localparam [31:0] REG_CTRL        = BASE_ADDR + 32'h00;
    localparam [31:0] REG_STATUS      = BASE_ADDR + 32'h04;
    localparam [31:0] REG_INPUT_H     = BASE_ADDR + 32'h08;
    localparam [31:0] REG_INPUT_W     = BASE_ADDR + 32'h0C;
    localparam [31:0] REG_CIN         = BASE_ADDR + 32'h10;
    localparam [31:0] REG_COUT        = BASE_ADDR + 32'h14;
    localparam [31:0] REG_KERNEL_SIZE = BASE_ADDR + 32'h18;
    localparam [31:0] REG_STRIDE      = BASE_ADDR + 32'h1C;
    localparam [31:0] REG_PADDING     = BASE_ADDR + 32'h20;
    localparam [31:0] REG_RELU_EN     = BASE_ADDR + 32'h24;
    localparam [31:0] REG_OUT_H       = BASE_ADDR + 32'h28;
    localparam [31:0] REG_OUT_W       = BASE_ADDR + 32'h2C;
    localparam [31:0] REG_INPUT_DATA  = BASE_ADDR + 32'h30;
    localparam [31:0] REG_WEIGHT_DATA = BASE_ADDR + 32'h34;
    localparam [31:0] REG_OUTPUT_DATA = BASE_ADDR + 32'h38;
    localparam [31:0] REG_INPUT_COUNT = BASE_ADDR + 32'h3C;
    localparam [31:0] REG_WEIGHT_COUNT= BASE_ADDR + 32'h40;
    localparam [31:0] REG_OUTPUT_COUNT= BASE_ADDR + 32'h44;
    localparam [31:0] REG_ERROR_CODE  = BASE_ADDR + 32'h48;

    // CTRL bits
    localparam [31:0] CTRL_START = 32'h0000_0001;
    localparam [31:0] CTRL_CLEAR = 32'h0000_0002;

    // DUT Inputs
    reg         clk;
    reg         rst;

    reg [31:0]  mmio_addr;
    reg [31:0]  mmio_wdata;
    reg         mmio_we;
    reg         mmio_re;

    reg [31:0]  compute_output_data;
    reg [31:0]  compute_output_count;

    reg         compute_done;
    reg         compute_error;
    reg [31:0]  compute_error_code;

    // DUT Outputs
    wire [31:0] mmio_rdata;
    wire        mmio_hit;

    wire [15:0] cfg_input_h;
    wire [15:0] cfg_input_w;
    wire [15:0] cfg_cin;
    wire [15:0] cfg_cout;

    wire [7:0]  cfg_kernel_size;
    wire [7:0]  cfg_stride;
    wire [7:0]  cfg_padding;
    wire        cfg_relu_en;

    wire [31:0] input_data_word;
    wire        input_data_valid;

    wire [31:0] weight_data_word;
    wire        weight_data_valid;

    wire        output_read_pulse;
    wire        core_enable;

    // Testbench Variables
    integer pass_count;
    integer fail_count;
    integer i;

    reg [31:0] read_data;

    // DUT
    accelerator_control_top #(
        .BASE_ADDR(BASE_ADDR)
    ) dut (
        .clk(clk),
        .rst(rst),

        .mmio_addr(mmio_addr),
        .mmio_wdata(mmio_wdata),
        .mmio_we(mmio_we),
        .mmio_re(mmio_re),

        .mmio_rdata(mmio_rdata),
        .mmio_hit(mmio_hit),

        .cfg_input_h(cfg_input_h),
        .cfg_input_w(cfg_input_w),
        .cfg_cin(cfg_cin),
        .cfg_cout(cfg_cout),

        .cfg_kernel_size(cfg_kernel_size),
        .cfg_stride(cfg_stride),
        .cfg_padding(cfg_padding),
        .cfg_relu_en(cfg_relu_en),

        .input_data_word(input_data_word),
        .input_data_valid(input_data_valid),

        .weight_data_word(weight_data_word),
        .weight_data_valid(weight_data_valid),

        .compute_output_data(compute_output_data),
        .compute_output_count(compute_output_count),
        .output_read_pulse(output_read_pulse),

        .compute_done(compute_done),
        .compute_error(compute_error),
        .compute_error_code(compute_error_code),

        .core_enable(core_enable)
    );

    // 100 MHz Clock
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Waveform Dump
    initial begin
        $dumpfile("tb_accelerator_control_top.vcd");
        $dumpvars(0, tb_accelerator_control_top);
    end

    // MMIO Write Task
    task mmio_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(negedge clk);
            mmio_addr  = addr;
            mmio_wdata = data;
            mmio_we    = 1'b1;
            mmio_re    = 1'b0;

            @(posedge clk);
            #1;

            @(negedge clk);
            mmio_we    = 1'b0;
            mmio_addr  = 32'd0;
            mmio_wdata = 32'd0;
        end
    endtask

    // MMIO Read Task
    task mmio_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(negedge clk);
            mmio_addr = addr;
            mmio_we   = 1'b0;
            mmio_re   = 1'b1;

            #1;
            data = mmio_rdata;

            @(negedge clk);
            mmio_re   = 1'b0;
            mmio_addr = 32'd0;
        end
    endtask

    // 32-bit Check Task
    task check32;
        input [8*80-1:0] name;
        input [31:0] got;
        input [31:0] expected;
        begin
            if (got === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s | got=0x%08h", name, got);
            end
            else begin
                fail_count = fail_count + 1;
                $display(
                    "[FAIL] %0s | got=0x%08h expected=0x%08h",
                    name, got, expected
                );
            end
        end
    endtask

    // 1-bit Check Task
    task check1;
        input [8*80-1:0] name;
        input got;
        input expected;
        begin
            if (got === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s | got=%b", name, got);
            end
            else begin
                fail_count = fail_count + 1;
                $display(
                    "[FAIL] %0s | got=%b expected=%b",
                    name, got, expected
                );
            end
        end
    endtask

    // Pulse compute_done for one clock
    task pulse_compute_done;
        begin
            @(negedge clk);
            compute_done = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);
            compute_done = 1'b0;
        end
    endtask

    // Pulse compute_error for one clock
    task pulse_compute_error;
        input [31:0] code;
        begin
            @(negedge clk);
            compute_error      = 1'b1;
            compute_error_code = code;

            @(posedge clk);
            #1;

            @(negedge clk);
            compute_error      = 1'b0;
            compute_error_code = 32'd0;
        end
    endtask

    // ============================================================
    // Load Conv1 Configuration
    //
    // H=28 W=28 Cin=1 Cout=16 K=3 S=1 P=1 ReLU=1
    // Input count  = 784
    // Weight count = 144
    // ============================================================
    task program_conv1_config;
        begin
            mmio_write(REG_INPUT_H,     32'd28);
            mmio_write(REG_INPUT_W,     32'd28);
            mmio_write(REG_CIN,         32'd1);
            mmio_write(REG_COUT,        32'd16);
            mmio_write(REG_KERNEL_SIZE, 32'd3);
            mmio_write(REG_STRIDE,      32'd1);
            mmio_write(REG_PADDING,     32'd1);
            mmio_write(REG_RELU_EN,     32'd1);
        end
    endtask

    // ============================================================
    // Load Full Conv1 Input / Weight Counts
    //
    // Each MMIO write carries 4 INT8 values.
    // 784 / 4 = 196 input writes
    // 144 / 4 = 36 weight writes
    // ============================================================
    task load_conv1_data;
        begin
            for (i = 0; i < 196; i = i + 1)
                mmio_write(REG_INPUT_DATA, 32'h0403_0201);

            for (i = 0; i < 36; i = i + 1)
                mmio_write(REG_WEIGHT_DATA, 32'h0807_0605);
        end
    endtask

    // Main Test Sequence
    initial begin
        // Initial values
        pass_count = 0;
        fail_count = 0;

        rst        = 1'b1;

        mmio_addr  = 32'd0;
        mmio_wdata = 32'd0;
        mmio_we    = 1'b0;
        mmio_re    = 1'b0;

        compute_output_data  = 32'h1234_5678;
        compute_output_count = 32'd0;

        compute_done       = 1'b0;
        compute_error      = 1'b0;
        compute_error_code = 32'd0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        repeat (2) @(posedge clk);
        #1;

        $display("");
        $display("==================================================");
        $display(" AI Accelerator Control Top Integration Testbench");
        $display("==================================================");
        $display("");

        // ========================================================
        // TEST 1: Reset / Initial STATUS
        // ========================================================
        $display("---- TEST 1: Reset / Initial State ----");

        mmio_read(REG_STATUS, read_data);
        check32("STATUS after reset", read_data, 32'h0000_0000);

        check1("core_enable after reset", core_enable, 1'b0);

        // ========================================================
        // TEST 2: Program Conv1 Configuration
        // ========================================================
        $display("");
        $display("---- TEST 2: Program Conv1 Configuration ----");

        program_conv1_config();

        check32("cfg_input_h",     {16'd0, cfg_input_h},     32'd28);
        check32("cfg_input_w",     {16'd0, cfg_input_w},     32'd28);
        check32("cfg_cin",         {16'd0, cfg_cin},         32'd1);
        check32("cfg_cout",        {16'd0, cfg_cout},        32'd16);
        check32("cfg_kernel_size", {24'd0, cfg_kernel_size}, 32'd3);
        check32("cfg_stride",      {24'd0, cfg_stride},      32'd1);
        check32("cfg_padding",     {24'd0, cfg_padding},     32'd1);
        check32("cfg_relu_en",     {31'd0, cfg_relu_en},     32'd1);

        mmio_read(REG_OUT_H, read_data);
        check32("OUT_H for Conv1", read_data, 32'd28);

        mmio_read(REG_OUT_W, read_data);
        check32("OUT_W for Conv1", read_data, 32'd28);

        // ========================================================
        // TEST 3: Load Complete Conv1 Input and Weight Data
        // ========================================================
        $display("");
        $display("---- TEST 3: Load Conv1 Data ----");

        load_conv1_data();

        mmio_read(REG_INPUT_COUNT, read_data);
        check32("INPUT_COUNT = 784", read_data, 32'd784);

        mmio_read(REG_WEIGHT_COUNT, read_data);
        check32("WEIGHT_COUNT = 144", read_data, 32'd144);

        // ========================================================
        // TEST 4: START -> CHECK -> RUN
        // ========================================================
        $display("");
        $display("---- TEST 4: Valid START Flow ----");

        mmio_write(REG_CTRL, CTRL_START);

        // Allow START pulse to reach controller.
        repeat (2) @(posedge clk);
        #1;

        check1("core_enable in RUN", core_enable, 1'b1);

        mmio_read(REG_STATUS, read_data);

        // STATUS bit0 = BUSY
        check1("STATUS.BUSY in RUN", read_data[0], 1'b1);
        check1("STATUS.DONE in RUN", read_data[1], 1'b0);
        check1("STATUS.ERROR in RUN", read_data[2], 1'b0);

        // ========================================================
        // TEST 5: RUN -> DONE
        // ========================================================
        $display("");
        $display("---- TEST 5: Compute DONE Flow ----");

        compute_output_count = 32'd12544;
        pulse_compute_done();

        // Allow controller and MMIO latch to settle.
        repeat (2) @(posedge clk);
        #1;

        check1("core_enable after DONE", core_enable, 1'b0);

        mmio_read(REG_STATUS, read_data);
        check1("STATUS.BUSY after DONE", read_data[0], 1'b0);
        check1("STATUS.DONE after DONE", read_data[1], 1'b1);
        check1("STATUS.ERROR after DONE", read_data[2], 1'b0);

        mmio_read(REG_OUTPUT_COUNT, read_data);
        check32("OUTPUT_COUNT passthrough", read_data, 32'd12544);

        // ========================================================
        // TEST 6: Read OUTPUT_DATA
        // ========================================================
        $display("");
        $display("---- TEST 6: Output Read ----");

        mmio_read(REG_OUTPUT_DATA, read_data);
        check32("OUTPUT_DATA read", read_data, 32'h1234_5678);

        // output_read_pulse is a one-cycle event. Re-read while
        // holding the MMIO read long enough to observe the pulse.
        @(negedge clk);
        mmio_addr = REG_OUTPUT_DATA;
        mmio_re   = 1'b1;

        @(posedge clk);
        #1;
        check1("output_read_pulse", output_read_pulse, 1'b1);

        @(negedge clk);
        mmio_re   = 1'b0;
        mmio_addr = 32'd0;

        // ========================================================
        // TEST 7: CLEAR from DONE
        // ========================================================
        $display("");
        $display("---- TEST 7: CLEAR after DONE ----");

        mmio_write(REG_CTRL, CTRL_CLEAR);

        repeat (2) @(posedge clk);
        #1;

        mmio_read(REG_STATUS, read_data);
        check32("STATUS after CLEAR", read_data, 32'h0000_0000);

        mmio_read(REG_INPUT_COUNT, read_data);
        check32("INPUT_COUNT cleared", read_data, 32'd0);

        mmio_read(REG_WEIGHT_COUNT, read_data);
        check32("WEIGHT_COUNT cleared", read_data, 32'd0);

        check1("core_enable after CLEAR", core_enable, 1'b0);

        // ========================================================
        // TEST 8: Validation Failure
        //
        // Keep valid config but load only one input word and one
        // weight word. Expected counts are still 784 and 144.
        // ========================================================
        $display("");
        $display("---- TEST 8: Validation Failure ----");

        program_conv1_config();

        mmio_write(REG_INPUT_DATA,  32'h0403_0201);
        mmio_write(REG_WEIGHT_DATA, 32'h0807_0605);

        mmio_write(REG_CTRL, CTRL_START);

        // START -> CHECK -> ERROR
        repeat (3) @(posedge clk);
        #1;

        check1("core_enable on validation error", core_enable, 1'b0);

        mmio_read(REG_STATUS, read_data);
        check1("STATUS.BUSY validation error",  read_data[0], 1'b0);
        check1("STATUS.DONE validation error",  read_data[1], 1'b0);
        check1("STATUS.ERROR validation error", read_data[2], 1'b1);

        mmio_read(REG_ERROR_CODE, read_data);
        check32("Validation ERROR_CODE", read_data, 32'h0000_0001);

        // ========================================================
        // TEST 9: CLEAR from ERROR
        // ========================================================
        $display("");
        $display("---- TEST 9: CLEAR after ERROR ----");

        mmio_write(REG_CTRL, CTRL_CLEAR);

        repeat (2) @(posedge clk);
        #1;

        mmio_read(REG_STATUS, read_data);
        check32("STATUS after ERROR CLEAR", read_data, 32'h0000_0000);

        mmio_read(REG_ERROR_CODE, read_data);
        check32("ERROR_CODE cleared", read_data, 32'h0000_0000);

        // ========================================================
        // TEST 10: Compute Error During RUN
        // ========================================================
        $display("");
        $display("---- TEST 10: Compute Error Flow ----");

        program_conv1_config();
        load_conv1_data();

        mmio_write(REG_CTRL, CTRL_START);

        repeat (2) @(posedge clk);
        #1;

        check1("RUN before compute_error", core_enable, 1'b1);

        pulse_compute_error(32'h0000_00AA);

        repeat (2) @(posedge clk);
        #1;

        check1("core_enable after compute_error", core_enable, 1'b0);

        mmio_read(REG_STATUS, read_data);
        check1("STATUS.ERROR after compute_error", read_data[2], 1'b1);

        mmio_read(REG_ERROR_CODE, read_data);
        check32("Compute ERROR_CODE passthrough",
                read_data,
                32'h0000_00AA);

        // ========================================================
        // Final Cleanup
        // ========================================================
        mmio_write(REG_CTRL, CTRL_CLEAR);

        repeat (2) @(posedge clk);
        #1;

        // ========================================================
        // Final Summary
        // ========================================================
        $display("");
        $display("==================================================");
        $display(" TEST SUMMARY");
        $display("==================================================");
        $display(" PASS = %0d", pass_count);
        $display(" FAIL = %0d", fail_count);

        if (fail_count == 0)
            $display(" RESULT: ALL TESTS PASSED");
        else
            $display(" RESULT: TESTBENCH FAILED");

        $display(" VCD: tb_accelerator_control_top.vcd");
        $display("==================================================");
        $display("");

        repeat (3) @(posedge clk);
        $finish;
    end

endmodule
