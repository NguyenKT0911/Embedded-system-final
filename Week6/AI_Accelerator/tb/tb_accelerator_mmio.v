`timescale 1ns/1ps

module tb_accelerator_mmio;

    // Base Address
    localparam [31:0] BASE_ADDR = 32'h4000_0000;

    // Register offsets used by the testbench
    localparam [31:0] ADDR_CTRL         = BASE_ADDR + 32'h00;
    localparam [31:0] ADDR_STATUS       = BASE_ADDR + 32'h04;
    localparam [31:0] ADDR_INPUT_H      = BASE_ADDR + 32'h08;
    localparam [31:0] ADDR_INPUT_W      = BASE_ADDR + 32'h0C;
    localparam [31:0] ADDR_CIN          = BASE_ADDR + 32'h10;
    localparam [31:0] ADDR_COUT         = BASE_ADDR + 32'h14;
    localparam [31:0] ADDR_KERNEL_SIZE  = BASE_ADDR + 32'h18;
    localparam [31:0] ADDR_STRIDE       = BASE_ADDR + 32'h1C;
    localparam [31:0] ADDR_PADDING      = BASE_ADDR + 32'h20;
    localparam [31:0] ADDR_RELU_EN      = BASE_ADDR + 32'h24;
    localparam [31:0] ADDR_OUT_H        = BASE_ADDR + 32'h28;
    localparam [31:0] ADDR_OUT_W        = BASE_ADDR + 32'h2C;
    localparam [31:0] ADDR_INPUT_DATA   = BASE_ADDR + 32'h30;
    localparam [31:0] ADDR_WEIGHT_DATA  = BASE_ADDR + 32'h34;
    localparam [31:0] ADDR_OUTPUT_DATA  = BASE_ADDR + 32'h38;
    localparam [31:0] ADDR_INPUT_COUNT  = BASE_ADDR + 32'h3C;
    localparam [31:0] ADDR_WEIGHT_COUNT = BASE_ADDR + 32'h40;
    localparam [31:0] ADDR_OUTPUT_COUNT = BASE_ADDR + 32'h44;
    localparam [31:0] ADDR_ERROR_CODE   = BASE_ADDR + 32'h48;

    // Clock and Reset
    reg clk;
    reg rst;

    // RISC-V MMIO Interface
    reg  [31:0] mmio_addr;
    reg  [31:0] mmio_wdata;
    reg         mmio_we;
    reg         mmio_re;

    wire [31:0] mmio_rdata;
    wire        mmio_hit;

    // Control Outputs
    wire start_pulse;
    wire clear_pulse;

    // Configuration Outputs
    wire [15:0] input_h;
    wire [15:0] input_w;
    wire [15:0] cin;
    wire [15:0] cout;

    wire [7:0] kernel_size;
    wire [7:0] stride;
    wire [7:0] padding;

    wire relu_en;

    // ============================================================
    // Validation / Counter Outputs
    // ============================================================
    wire [31:0] input_count_value;
    wire [31:0] weight_count_value;


    // Input Activation Interface
    wire [31:0] input_data_word;
    wire        input_data_valid;

    // Weight Interface
    wire [31:0] weight_data_word;
    wire        weight_data_valid;

    // Output Interface
    reg  [31:0] core_output_data;
    reg  [31:0] core_output_count;

    wire        output_read_pulse;

    // Accelerator Core Status
    reg         core_busy;
    reg         core_done;
    reg         core_error;
    reg [31:0]  core_error_code;

    // Testbench Variables
    reg [31:0] read_data;

    integer pass_count;
    integer fail_count;

    // DUT
    accelerator_mmio #(
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

        .start_pulse(start_pulse),
        .clear_pulse(clear_pulse),

        .input_h(input_h),
        .input_w(input_w),
        .cin(cin),
        .cout(cout),

        .kernel_size(kernel_size),
        .stride(stride),
        .padding(padding),
        .relu_en(relu_en),

        .input_count_value(input_count_value),
        .weight_count_value(weight_count_value),

        .input_data_word(input_data_word),
        .input_data_valid(input_data_valid),

        .weight_data_word(weight_data_word),
        .weight_data_valid(weight_data_valid),

        .core_output_data(core_output_data),
        .core_output_count(core_output_count),
        .output_read_pulse(output_read_pulse),

        .core_busy(core_busy),
        .core_done(core_done),
        .core_error(core_error),
        .core_error_code(core_error_code)
    );

    // Clock Generation
    // 10 ns period = 100 MHz
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Waveform Dump
    initial begin
        $dumpfile("tb_accelerator_mmio.vcd");
        $dumpvars(0, tb_accelerator_mmio);
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

            // DUT captures the write at this rising edge.
            @(posedge clk);
            #1;

            // Release the bus at the following falling edge.
            @(negedge clk);

            mmio_we    = 1'b0;
            mmio_re    = 1'b0;
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

            mmio_addr  = addr;
            mmio_wdata = 32'd0;
            mmio_we    = 1'b0;
            mmio_re    = 1'b1;

            // Hold the request across one rising edge.
            // This also allows read side effects such as
            // OUTPUT_DATA -> output_read_pulse.
            @(posedge clk);
            #1;

            data = mmio_rdata;

            @(negedge clk);

            mmio_re    = 1'b0;
            mmio_we    = 1'b0;
            mmio_addr  = 32'd0;
            mmio_wdata = 32'd0;
        end
    endtask

    // Check Helpers
    task check32;
        input [8*64-1:0] name;
        input [31:0] got;
        input [31:0] expected;

        begin
            if (got === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s : got=0x%08h", name, got);
            end
            else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s : got=0x%08h expected=0x%08h",
                         name, got, expected);
            end
        end
    endtask

    task check1;
        input [8*64-1:0] name;
        input got;
        input expected;

        begin
            if (got === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s : got=%b", name, got);
            end
            else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s : got=%b expected=%b",
                         name, got, expected);
            end
        end
    endtask

    // Core Status Pulse Helpers
    task pulse_core_done;
        begin
            @(negedge clk);
            core_done = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);
            core_done = 1'b0;
        end
    endtask

    task pulse_core_error;
        input [31:0] error_code;

        begin
            @(negedge clk);
            core_error      = 1'b1;
            core_error_code = error_code;

            @(posedge clk);
            #1;

            @(negedge clk);
            core_error      = 1'b0;
            core_error_code = 32'd0;
        end
    endtask

    // Test Sequence
    initial begin
        // Initial Values
        pass_count = 0;
        fail_count = 0;

        rst = 1'b1;

        mmio_addr  = 32'd0;
        mmio_wdata = 32'd0;
        mmio_we    = 1'b0;
        mmio_re    = 1'b0;

        core_busy       = 1'b0;
        core_done       = 1'b0;
        core_error      = 1'b0;
        core_error_code = 32'd0;

        core_output_data  = 32'd0;
        core_output_count = 32'd0;

        // Reset
        repeat (3) @(posedge clk);

        @(negedge clk);
        rst = 1'b0;

        $display("");
        $display("==========================================");
        $display(" AI Accelerator MMIO Testbench");
        $display("==========================================");
        $display("Reset released.");
        $display("");

        // TEST 1: Reset State
        $display("---- TEST 1: Reset State ----");

        check32("input_h after reset",         {16'd0, input_h},          32'd0);
        check32("input_w after reset",         {16'd0, input_w},          32'd0);
        check32("cin after reset",             {16'd0, cin},              32'd0);
        check32("cout after reset",            {16'd0, cout},             32'd0);
        check1 ("start_pulse after reset",     start_pulse,               1'b0);
        check1 ("clear_pulse after reset",     clear_pulse,               1'b0);
        check1 ("input_data_valid reset",      input_data_valid,          1'b0);
        check1 ("weight_data_valid reset",     weight_data_valid,         1'b0);
        check1 ("output_read_pulse reset",     output_read_pulse,         1'b0);

        // TEST 2: Address Decode
        $display("");
        $display("---- TEST 2: Address Decode ----");

        @(negedge clk);
        mmio_addr = ADDR_INPUT_H;
        #1;
        check1("valid MMIO address hit", mmio_hit, 1'b1);

        mmio_addr = BASE_ADDR + 32'h09; // intentionally misaligned
        #1;
        check1("misaligned address rejected", mmio_hit, 1'b0);

        mmio_addr = BASE_ADDR + 32'h4C; // outside defined window
        #1;
        check1("out-of-range address rejected", mmio_hit, 1'b0);

        mmio_addr = 32'd0;

        // TEST 3: Configuration Register Write/Read
        // Conv1 configuration
        $display("");
        $display("---- TEST 3: Configuration Registers ----");

        mmio_write(ADDR_INPUT_H,     32'd28);
        mmio_write(ADDR_INPUT_W,     32'd28);
        mmio_write(ADDR_CIN,         32'd1);
        mmio_write(ADDR_COUT,        32'd16);
        mmio_write(ADDR_KERNEL_SIZE, 32'd3);
        mmio_write(ADDR_STRIDE,      32'd1);
        mmio_write(ADDR_PADDING,     32'd1);
        mmio_write(ADDR_RELU_EN,     32'd1);

        mmio_read(ADDR_INPUT_H, read_data);
        check32("INPUT_H", read_data, 32'd28);

        mmio_read(ADDR_INPUT_W, read_data);
        check32("INPUT_W", read_data, 32'd28);

        mmio_read(ADDR_CIN, read_data);
        check32("CIN", read_data, 32'd1);

        mmio_read(ADDR_COUT, read_data);
        check32("COUT", read_data, 32'd16);

        mmio_read(ADDR_KERNEL_SIZE, read_data);
        check32("KERNEL_SIZE", read_data, 32'd3);

        mmio_read(ADDR_STRIDE, read_data);
        check32("STRIDE", read_data, 32'd1);

        mmio_read(ADDR_PADDING, read_data);
        check32("PADDING", read_data, 32'd1);

        mmio_read(ADDR_RELU_EN, read_data);
        check32("RELU_EN", read_data, 32'd1);

        mmio_read(ADDR_OUT_H, read_data);
        check32("OUT_H", read_data, 32'd28);

        mmio_read(ADDR_OUT_W, read_data);
        check32("OUT_W", read_data, 32'd28);

        // TEST 4: INPUT_DATA Write and Counter
        $display("");
        $display("---- TEST 4: INPUT_DATA ----");

        mmio_write(ADDR_INPUT_DATA, 32'h641E_FB0C);

        check32("input_data_word",
                input_data_word,
                32'h641E_FB0C);

        check1("input_data_valid pulse",
               input_data_valid,
               1'b1);

        mmio_read(ADDR_INPUT_COUNT, read_data);
        check32("INPUT_COUNT after one word",
                read_data,
                32'd4);

        // After another rising edge, the valid pulse must disappear.
        @(posedge clk);
        #1;
        check1("input_data_valid returns low",
               input_data_valid,
               1'b0);

        // TEST 5: WEIGHT_DATA Write and Counter
        $display("");
        $display("---- TEST 5: WEIGHT_DATA ----");

        mmio_write(ADDR_WEIGHT_DATA, 32'h0403_0201);

        check32("weight_data_word",
                weight_data_word,
                32'h0403_0201);

        check1("weight_data_valid pulse",
               weight_data_valid,
               1'b1);

        mmio_read(ADDR_WEIGHT_COUNT, read_data);
        check32("WEIGHT_COUNT after one word",
                read_data,
                32'd4);

        @(posedge clk);
        #1;
        check1("weight_data_valid returns low",
               weight_data_valid,
               1'b0);

        // TEST 6: START Pulse
        $display("");
        $display("---- TEST 6: START Pulse ----");

        mmio_write(ADDR_CTRL, 32'h0000_0001);

        check1("START asserted for one cycle",
               start_pulse,
               1'b1);

        @(posedge clk);
        #1;
        check1("START returns low",
               start_pulse,
               1'b0);

        // TEST 7: STATUS.BUSY and Busy Write Protection
        $display("");
        $display("---- TEST 7: BUSY Status / Write Protection ----");

        core_busy = 1'b1;

        mmio_read(ADDR_STATUS, read_data);
        check32("STATUS while BUSY",
                read_data,
                32'h0000_0001);

        // Configuration writes are ignored while core_busy = 1.
        mmio_write(ADDR_INPUT_H, 32'd99);

        mmio_read(ADDR_INPUT_H, read_data);
        check32("INPUT_H unchanged while BUSY",
                read_data,
                32'd28);

        core_busy = 1'b0;

        // TEST 8: DONE Latch
        $display("");
        $display("---- TEST 8: DONE Status ----");

        pulse_core_done();

        mmio_read(ADDR_STATUS, read_data);
        check32("STATUS after core_done",
                read_data,
                32'h0000_0002);

        // TEST 9: OUTPUT_COUNT and OUTPUT_DATA
        $display("");
        $display("---- TEST 9: Output Read ----");

        core_output_count = 32'd3;
        core_output_data  = 32'hFFFF_FFD0; // -48 as signed INT32

        mmio_read(ADDR_OUTPUT_COUNT, read_data);
        check32("OUTPUT_COUNT",
                read_data,
                32'd3);

        mmio_read(ADDR_OUTPUT_DATA, read_data);

        check32("OUTPUT_DATA",
                read_data,
                32'hFFFF_FFD0);

        check1("output_read_pulse asserted",
               output_read_pulse,
               1'b1);

        @(posedge clk);
        #1;
        check1("output_read_pulse returns low",
               output_read_pulse,
               1'b0);

        // TEST 10: CLEAR
        $display("");
        $display("---- TEST 10: CLEAR ----");

        mmio_write(ADDR_CTRL, 32'h0000_0002);

        check1("CLEAR asserted for one cycle",
               clear_pulse,
               1'b1);

        mmio_read(ADDR_STATUS, read_data);
        check32("STATUS after CLEAR",
                read_data,
                32'd0);

        mmio_read(ADDR_INPUT_COUNT, read_data);
        check32("INPUT_COUNT after CLEAR",
                read_data,
                32'd0);

        mmio_read(ADDR_WEIGHT_COUNT, read_data);
        check32("WEIGHT_COUNT after CLEAR",
                read_data,
                32'd0);

        @(posedge clk);
        #1;
        check1("CLEAR returns low",
               clear_pulse,
               1'b0);

        // TEST 11: ERROR Latch and ERROR_CODE
        $display("");
        $display("---- TEST 11: ERROR Status ----");

        pulse_core_error(32'h0000_0005);

        mmio_read(ADDR_STATUS, read_data);
        check32("STATUS after core_error",
                read_data,
                32'h0000_0004);

        mmio_read(ADDR_ERROR_CODE, read_data);
        check32("ERROR_CODE",
                read_data,
                32'h0000_0005);

        // Clear the error before ending the test.
        mmio_write(ADDR_CTRL, 32'h0000_0002);

        mmio_read(ADDR_STATUS, read_data);
        check32("STATUS after final CLEAR",
                read_data,
                32'd0);

        // Final Summary
        $display("");
        $display("==========================================");
        $display(" TEST SUMMARY");
        $display("==========================================");
        $display(" PASS = %0d", pass_count);
        $display(" FAIL = %0d", fail_count);

        if (fail_count == 0)
            $display(" RESULT: ALL TESTS PASSED");
        else
            $display(" RESULT: TESTBENCH FAILED");

        $display(" VCD: tb_accelerator_mmio.vcd");
        $display("==========================================");
        $display("");

        repeat (3) @(posedge clk);
        $finish;
    end

endmodule
