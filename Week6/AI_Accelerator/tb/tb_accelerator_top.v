`timescale 1ns/1ps

module tb_accelerator_top;

    // ============================================================
    // MMIO Base / Register Map
    // ============================================================
    localparam [31:0] BASE_ADDR = 32'h4000_0000;

    localparam [31:0] REG_CTRL         = BASE_ADDR + 32'h00;
    localparam [31:0] REG_STATUS       = BASE_ADDR + 32'h04;

    localparam [31:0] REG_INPUT_H      = BASE_ADDR + 32'h08;
    localparam [31:0] REG_INPUT_W      = BASE_ADDR + 32'h0C;
    localparam [31:0] REG_CIN          = BASE_ADDR + 32'h10;
    localparam [31:0] REG_COUT         = BASE_ADDR + 32'h14;

    localparam [31:0] REG_KERNEL_SIZE  = BASE_ADDR + 32'h18;
    localparam [31:0] REG_STRIDE       = BASE_ADDR + 32'h1C;
    localparam [31:0] REG_PADDING      = BASE_ADDR + 32'h20;
    localparam [31:0] REG_RELU_EN      = BASE_ADDR + 32'h24;

    localparam [31:0] REG_OUT_H        = BASE_ADDR + 32'h28;
    localparam [31:0] REG_OUT_W        = BASE_ADDR + 32'h2C;

    localparam [31:0] REG_INPUT_DATA   = BASE_ADDR + 32'h30;
    localparam [31:0] REG_WEIGHT_DATA  = BASE_ADDR + 32'h34;
    localparam [31:0] REG_OUTPUT_DATA  = BASE_ADDR + 32'h38;

    localparam [31:0] REG_INPUT_COUNT  = BASE_ADDR + 32'h3C;
    localparam [31:0] REG_WEIGHT_COUNT = BASE_ADDR + 32'h40;
    localparam [31:0] REG_OUTPUT_COUNT = BASE_ADDR + 32'h44;
    localparam [31:0] REG_ERROR_CODE   = BASE_ADDR + 32'h48;

    // CTRL bits
    localparam [31:0] CTRL_START = 32'h0000_0001;
    localparam [31:0] CTRL_CLEAR = 32'h0000_0002;

    // ============================================================
    // Small End-to-End Test Configuration
    //
    // Input  : 1 x 4 x 4
    // Weight : 4 x 1 x 3 x 3
    // Output : 4 x 4 x 4 = 64 INT32 values
    // ============================================================
    localparam integer INPUT_MAX_VALUES  = 16;
    localparam integer WEIGHT_MAX_VALUES = 36;
    localparam integer OUTPUT_MAX_VALUES = 64;

    localparam integer INPUT_ADDR_WIDTH  = 4;
    localparam integer WEIGHT_ADDR_WIDTH = 6;
    localparam integer OUTPUT_ADDR_WIDTH = 6;

    // ============================================================
    // DUT Inputs
    // ============================================================
    reg clk;
    reg rst;

    reg [31:0] mmio_addr;
    reg [31:0] mmio_wdata;
    reg        mmio_we;
    reg        mmio_re;

    // ============================================================
    // DUT Outputs
    // ============================================================
    wire [31:0] mmio_rdata;
    wire        mmio_hit;

    wire        dbg_core_enable;
    wire        dbg_core_clear;

    wire        dbg_compute_busy;
    wire        dbg_compute_done;
    wire        dbg_compute_error;
    wire [31:0] dbg_compute_error_code;

    wire [31:0] dbg_input_buffer_count;
    wire [31:0] dbg_weight_buffer_count;
    wire [31:0] dbg_output_count;
    wire [31:0] dbg_output_read_index;

    // ============================================================
    // Golden Output
    // ============================================================
    reg signed [31:0] base_sum [0:15];
    reg signed [31:0] expected_output [0:63];

    // ============================================================
    // Test Counters
    // ============================================================
    integer pass_count;
    integer fail_count;

    integer timeout_count;
    integer i;
    integer oc;
    integer pos;

    reg [31:0] read_value;
    reg [31:0] status_value;

    // ============================================================
    // DUT
    // ============================================================
    accelerator_top #(
        .BASE_ADDR(BASE_ADDR),

        .INPUT_MAX_VALUES(INPUT_MAX_VALUES),
        .WEIGHT_MAX_VALUES(WEIGHT_MAX_VALUES),
        .OUTPUT_MAX_VALUES(OUTPUT_MAX_VALUES),

        .INPUT_ADDR_WIDTH(INPUT_ADDR_WIDTH),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH),
        .OUTPUT_ADDR_WIDTH(OUTPUT_ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),

        .mmio_addr(mmio_addr),
        .mmio_wdata(mmio_wdata),
        .mmio_we(mmio_we),
        .mmio_re(mmio_re),

        .mmio_rdata(mmio_rdata),
        .mmio_hit(mmio_hit),

        .dbg_core_enable(dbg_core_enable),
        .dbg_core_clear(dbg_core_clear),

        .dbg_compute_busy(dbg_compute_busy),
        .dbg_compute_done(dbg_compute_done),
        .dbg_compute_error(dbg_compute_error),
        .dbg_compute_error_code(dbg_compute_error_code),

        .dbg_input_buffer_count(dbg_input_buffer_count),
        .dbg_weight_buffer_count(dbg_weight_buffer_count),
        .dbg_output_count(dbg_output_count),
        .dbg_output_read_index(dbg_output_read_index)
    );

    // ============================================================
    // 100 MHz Clock
    // ============================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ============================================================
    // VCD
    // ============================================================
    initial begin
        $dumpfile("tb_accelerator_top.vcd");
        $dumpvars(0, tb_accelerator_top);
    end

    // ============================================================
    // MMIO Write
    // ============================================================
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

    // ============================================================
    // MMIO Read
    //
    // The extra rising edge after deasserting mmio_re is important
    // for REG_OUTPUT_DATA: MMIO creates output_read_pulse and the
    // output buffer consumes that pulse on the following clock.
    // ============================================================
    task mmio_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(negedge clk);

            mmio_addr = addr;
            mmio_we   = 1'b0;
            mmio_re   = 1'b1;

            // Combinational MMIO read value is already valid here,
            // but sample after the active edge for stable behavior.
            @(posedge clk);
            #1;

            data = mmio_rdata;

            @(negedge clk);

            mmio_re   = 1'b0;
            mmio_addr = 32'd0;

            // Allow registered read side effects to propagate.
            @(posedge clk);
            #1;
        end
    endtask

    // ============================================================
    // Wait for STATUS.DONE or STATUS.ERROR
    //
    // STATUS:
    //   bit 0 = BUSY
    //   bit 1 = DONE
    //   bit 2 = ERROR
    // ============================================================
    task wait_for_done_status;
        begin
            timeout_count = 0;
            status_value  = 32'd0;

            while ((status_value[1] !== 1'b1) &&
                   (status_value[2] !== 1'b1) &&
                   (timeout_count < 5000)) begin

                mmio_read(REG_STATUS, status_value);
                timeout_count = timeout_count + 1;

            end

            if ((status_value[1] !== 1'b1) &&
                (status_value[2] !== 1'b1)) begin

                fail_count = fail_count + 1;
                $display("[FAIL] Timeout waiting for STATUS.DONE/ERROR");

            end
        end
    endtask

    // ============================================================
    // Check Helpers
    // ============================================================
    task check1;
        input [8*96-1:0] name;
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

    task check32;
        input [8*96-1:0] name;
        input [31:0] got;
        input [31:0] expected;
        begin
            if (got === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s | got=%0d", name, got);
            end
            else begin
                fail_count = fail_count + 1;
                $display(
                    "[FAIL] %0s | got=%0d expected=%0d",
                    name, got, expected
                );
            end
        end
    endtask

    task check32h;
        input [8*96-1:0] name;
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

    task check32s;
        input [8*96-1:0] name;
        input signed [31:0] got;
        input signed [31:0] expected;
        begin
            if (got === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s | got=%0d", name, got);
            end
            else begin
                fail_count = fail_count + 1;
                $display(
                    "[FAIL] %0s | got=%0d expected=%0d",
                    name, got, expected
                );
            end
        end
    endtask

    // ============================================================
    // Golden Model for This Small RTL Test
    // ============================================================
    task build_expected_output;
        begin

            // 3x3 zero-padded sum for the 4x4 image:
            //
            //   1   2   3   4
            //   5   6   7   8
            //   9  10  11  12
            //  13  14  15  16
            base_sum[0]  = 32'sd14;
            base_sum[1]  = 32'sd24;
            base_sum[2]  = 32'sd30;
            base_sum[3]  = 32'sd22;

            base_sum[4]  = 32'sd33;
            base_sum[5]  = 32'sd54;
            base_sum[6]  = 32'sd63;
            base_sum[7]  = 32'sd45;

            base_sum[8]  = 32'sd57;
            base_sum[9]  = 32'sd90;
            base_sum[10] = 32'sd99;
            base_sum[11] = 32'sd69;

            base_sum[12] = 32'sd46;
            base_sum[13] = 32'sd72;
            base_sum[14] = 32'sd78;
            base_sum[15] = 32'sd54;

            // OC0 kernel all 1
            // OC1 kernel all 2
            // OC2 kernel all 3
            // OC3 kernel all 4
            //
            // Flattened output layout: [COUT][H][W]
            for (oc = 0; oc < 4; oc = oc + 1) begin
                for (pos = 0; pos < 16; pos = pos + 1) begin
                    expected_output[(oc * 16) + pos]
                        = base_sum[pos] * (oc + 1);
                end
            end

        end
    endtask

    // ============================================================
    // Global Watchdog
    // ============================================================
    initial begin
        #5000000;

        $display("");
        $display("[FAIL] GLOBAL TESTBENCH TIMEOUT");
        $finish;
    end

    // ============================================================
    // Main End-to-End Test
    // ============================================================
    initial begin

        pass_count = 0;
        fail_count = 0;

        rst        = 1'b1;

        mmio_addr  = 32'd0;
        mmio_wdata = 32'd0;
        mmio_we    = 1'b0;
        mmio_re    = 1'b0;

        build_expected_output();

        repeat (4) @(posedge clk);
        #1;

        $display("");
        $display("============================================================");
        $display(" FULL AI ACCELERATOR TOP END-TO-END TESTBENCH");
        $display("============================================================");
        $display("");

        // ========================================================
        // TEST 1: Reset / Address Decode
        // ========================================================
        $display("---- TEST 1: Reset / MMIO Decode ----");

        check1("mmio_hit low outside accelerator window",
               mmio_hit, 1'b0);

        check1("debug core_enable after reset",
               dbg_core_enable, 1'b0);

        check1("compute error after reset",
               dbg_compute_error, 1'b0);

        check32("input buffer count after reset",
                dbg_input_buffer_count, 32'd0);

        check32("weight buffer count after reset",
                dbg_weight_buffer_count, 32'd0);

        check32("output count after reset",
                dbg_output_count, 32'd0);

        @(negedge clk);
        rst = 1'b0;

        // ========================================================
        // TEST 2: MMIO CLEAR
        // ========================================================
        $display("");
        $display("---- TEST 2: MMIO CLEAR ----");

        mmio_write(REG_CTRL, CTRL_CLEAR);

        // Let the forwarded one-cycle clear reach compute core.
        repeat (2) @(posedge clk);
        #1;

        mmio_read(REG_STATUS, read_value);

        check1("STATUS.BUSY after clear",  read_value[0], 1'b0);
        check1("STATUS.DONE after clear",  read_value[1], 1'b0);
        check1("STATUS.ERROR after clear", read_value[2], 1'b0);

        check32("compute input count after clear",
                dbg_input_buffer_count, 32'd0);

        check32("compute weight count after clear",
                dbg_weight_buffer_count, 32'd0);

        check32("compute output count after clear",
                dbg_output_count, 32'd0);

        // ========================================================
        // TEST 3: Write Configuration Through MMIO
        // ========================================================
        $display("");
        $display("---- TEST 3: MMIO Configuration ----");

        mmio_write(REG_INPUT_H,     32'd4);
        mmio_write(REG_INPUT_W,     32'd4);
        mmio_write(REG_CIN,         32'd1);
        mmio_write(REG_COUT,        32'd4);

        mmio_write(REG_KERNEL_SIZE, 32'd3);
        mmio_write(REG_STRIDE,      32'd1);
        mmio_write(REG_PADDING,     32'd1);
        mmio_write(REG_RELU_EN,     32'd1);

        // Read back key config and derived shape.
        mmio_read(REG_INPUT_H, read_value);
        check32("INPUT_H readback", read_value, 32'd4);

        mmio_read(REG_INPUT_W, read_value);
        check32("INPUT_W readback", read_value, 32'd4);

        mmio_read(REG_CIN, read_value);
        check32("CIN readback", read_value, 32'd1);

        mmio_read(REG_COUT, read_value);
        check32("COUT readback", read_value, 32'd4);

        mmio_read(REG_OUT_H, read_value);
        check32("OUT_H readback", read_value, 32'd4);

        mmio_read(REG_OUT_W, read_value);
        check32("OUT_W readback", read_value, 32'd4);

        // ========================================================
        // TEST 4: Load Input Activation Through MMIO
        //
        // Packed order:
        //   [7:0]   first value
        //   [15:8]  second
        //   [23:16] third
        //   [31:24] fourth
        // ========================================================
        $display("");
        $display("---- TEST 4: MMIO Input Load ----");

        mmio_write(REG_INPUT_DATA, 32'h0403_0201);
        mmio_write(REG_INPUT_DATA, 32'h0807_0605);
        mmio_write(REG_INPUT_DATA, 32'h0C0B_0A09);
        mmio_write(REG_INPUT_DATA, 32'h100F_0E0D);

        mmio_read(REG_INPUT_COUNT, read_value);
        check32("MMIO INPUT_COUNT", read_value, 32'd16);

        check32("compute input buffer count",
                dbg_input_buffer_count, 32'd16);

        // ========================================================
        // TEST 5: Load Weights Through MMIO
        //
        // Weight layout: [COUT][CIN][KH][KW]
        //
        // OC0 = all 1
        // OC1 = all 2
        // OC2 = all 3
        // OC3 = all 4
        // ========================================================
        $display("");
        $display("---- TEST 5: MMIO Weight Load ----");

        mmio_write(REG_WEIGHT_DATA, 32'h0101_0101);
        mmio_write(REG_WEIGHT_DATA, 32'h0101_0101);
        mmio_write(REG_WEIGHT_DATA, 32'h0202_0201);

        mmio_write(REG_WEIGHT_DATA, 32'h0202_0202);
        mmio_write(REG_WEIGHT_DATA, 32'h0303_0202);
        mmio_write(REG_WEIGHT_DATA, 32'h0303_0303);

        mmio_write(REG_WEIGHT_DATA, 32'h0403_0303);
        mmio_write(REG_WEIGHT_DATA, 32'h0404_0404);
        mmio_write(REG_WEIGHT_DATA, 32'h0404_0404);

        mmio_read(REG_WEIGHT_COUNT, read_value);
        check32("MMIO WEIGHT_COUNT", read_value, 32'd36);

        check32("compute weight buffer count",
                dbg_weight_buffer_count, 32'd36);

        // ========================================================
        // TEST 6: START via MMIO
        // ========================================================
        $display("");
        $display("---- TEST 6: MMIO START / Automatic Full Run ----");

        mmio_write(REG_CTRL, CTRL_START);

        // The controller goes IDLE -> CHECK -> RUN.
        // Give it a few clocks and confirm RUN was reached.
        repeat (4) @(posedge clk);
        #1;

        if (dbg_core_enable || dbg_compute_busy) begin
            pass_count = pass_count + 1;
            $display("[PASS] accelerator entered compute RUN");
        end
        else begin
            fail_count = fail_count + 1;
            $display("[FAIL] accelerator did not enter compute RUN");
        end

        wait_for_done_status();

        check1("STATUS.DONE",  status_value[1], 1'b1);
        check1("STATUS.ERROR", status_value[2], 1'b0);
        check1("STATUS.BUSY after DONE", status_value[0], 1'b0);

        check1("debug compute_done", dbg_compute_done, 1'b1);
        check1("debug compute_error", dbg_compute_error, 1'b0);

        check32("debug compute error code",
                dbg_compute_error_code, 32'h0000_0000);

        // All output writes must be complete before DONE.
        mmio_read(REG_OUTPUT_COUNT, read_value);
        check32("MMIO OUTPUT_COUNT", read_value, 32'd64);

        check32("debug output count",
                dbg_output_count, 32'd64);

        // ========================================================
        // TEST 7: Read All 64 Outputs Through MMIO
        //
        // This is the final RISC-V-visible behavior:
        // repeatedly read OUTPUT_DATA after DONE.
        // ========================================================
        $display("");
        $display("---- TEST 7: MMIO Readback / Golden Comparison ----");

        for (i = 0; i < 64; i = i + 1) begin

            mmio_read(REG_OUTPUT_DATA, read_value);

            if ($signed(read_value) === expected_output[i]) begin

                pass_count = pass_count + 1;

                $display(
                    "[PASS] OUTPUT[%0d] = %0d",
                    i,
                    $signed(read_value)
                );

            end
            else begin

                fail_count = fail_count + 1;

                $display(
                    "[FAIL] OUTPUT[%0d] got=%0d expected=%0d",
                    i,
                    $signed(read_value),
                    expected_output[i]
                );

            end

        end

        check32("debug output read index after 64 MMIO reads",
                dbg_output_read_index, 32'd64);

        // ========================================================
        // TEST 8: Error Code Remains Clear
        // ========================================================
        $display("");
        $display("---- TEST 8: Final Error Status ----");

        mmio_read(REG_ERROR_CODE, read_value);
        check32h("ERROR_CODE", read_value, 32'h0000_0000);

        mmio_read(REG_STATUS, read_value);
        check1("STATUS.DONE still latched", read_value[1], 1'b1);
        check1("STATUS.ERROR remains clear", read_value[2], 1'b0);

        // ========================================================
        // TEST 9: Final CLEAR
        // ========================================================
        $display("");
        $display("---- TEST 9: Final CLEAR ----");

        mmio_write(REG_CTRL, CTRL_CLEAR);

        repeat (2) @(posedge clk);
        #1;

        mmio_read(REG_STATUS, read_value);

        check1("DONE cleared by CLEAR", read_value[1], 1'b0);
        check1("ERROR cleared by CLEAR", read_value[2], 1'b0);

        mmio_read(REG_INPUT_COUNT, read_value);
        check32("MMIO INPUT_COUNT cleared", read_value, 32'd0);

        mmio_read(REG_WEIGHT_COUNT, read_value);
        check32("MMIO WEIGHT_COUNT cleared", read_value, 32'd0);

        check32("compute input buffer cleared",
                dbg_input_buffer_count, 32'd0);

        check32("compute weight buffer cleared",
                dbg_weight_buffer_count, 32'd0);

        check32("compute output buffer cleared",
                dbg_output_count, 32'd0);

        check32("compute output read pointer cleared",
                dbg_output_read_index, 32'd0);

        // ========================================================
        // Final Summary
        // ========================================================
        $display("");
        $display("============================================================");
        $display(" TEST SUMMARY");
        $display("============================================================");
        $display(" PASS = %0d", pass_count);
        $display(" FAIL = %0d", fail_count);

        if (fail_count == 0)
            $display(" RESULT: ALL TESTS PASSED");
        else
            $display(" RESULT: TESTBENCH FAILED");

        $display(" VCD: tb_accelerator_top.vcd");
        $display("============================================================");
        $display("");

        repeat (3) @(posedge clk);
        $finish;
    end

endmodule
