`timescale 1ns/1ps

module tb_conv1_real_golden;

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

    localparam [31:0] CTRL_START = 32'h0000_0001;
    localparam [31:0] CTRL_CLEAR = 32'h0000_0002;

    // ============================================================
    // Conv1 configuration
    // ============================================================
    localparam integer INPUT_H       = 28;
    localparam integer INPUT_W       = 28;
    localparam integer CIN           = 1;
    localparam integer COUT          = 16;
    localparam integer KERNEL_SIZE   = 3;
    localparam integer STRIDE        = 1;
    localparam integer PADDING       = 1;
    localparam integer RELU_EN       = 1;
    localparam integer OUT_H         = 28;
    localparam integer OUT_W         = 28;

    localparam integer INPUT_VALUES  = 784;
    localparam integer INPUT_WORDS   = 196;
    localparam integer WEIGHT_VALUES = 144;
    localparam integer WEIGHT_WORDS  = 36;
    localparam integer OUTPUT_VALUES = 12544;

    localparam integer INPUT_MAX_VALUES  = 3136;
    localparam integer WEIGHT_MAX_VALUES = 4608;
    localparam integer OUTPUT_MAX_VALUES = 12544;

    localparam integer INPUT_ADDR_WIDTH  = 12;
    localparam integer WEIGHT_ADDR_WIDTH = 13;
    localparam integer OUTPUT_ADDR_WIDTH = 14;

    // ============================================================
    // REAL MNIST golden files
    // Run simulation from AI_Accelerator project root
    // ============================================================
    localparam INPUT_HEX_FILE  =
        "verification/golden/conv1_real/conv1_real_input_packed32.hex";

    localparam WEIGHT_HEX_FILE =
        "verification/golden/conv1_real/conv1_real_weight_packed32.hex";

    localparam GOLDEN_HEX_FILE =
        "verification/golden/conv1_real/conv1_real_golden_int32.hex";

    reg clk;
    reg rst;

    reg [31:0] mmio_addr;
    reg [31:0] mmio_wdata;
    reg        mmio_we;
    reg        mmio_re;

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

    reg [31:0] input_words  [0:INPUT_WORDS-1];
    reg [31:0] weight_words [0:WEIGHT_WORDS-1];
    reg [31:0] golden_words [0:OUTPUT_VALUES-1];

    integer pass_count;
    integer fail_count;
    integer match_count;
    integer mismatch_count;
    integer timeout_count;
    integer i;

    reg [31:0] read_value;
    reg [31:0] status_value;

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

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("tb_conv1_real_golden.vcd");
        $dumpvars(0, tb_conv1_real_golden);
    end

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

    task mmio_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(negedge clk);
            mmio_addr = addr;
            mmio_we   = 1'b0;
            mmio_re   = 1'b1;

            @(posedge clk);
            #1;
            data = mmio_rdata;

            @(negedge clk);
            mmio_re   = 1'b0;
            mmio_addr = 32'd0;

            @(posedge clk);
            #1;
        end
    endtask

    task wait_for_done_status;
        begin
            timeout_count = 0;
            status_value  = 32'd0;

            while ((status_value[1] !== 1'b1) &&
                   (status_value[2] !== 1'b1) &&
                   (timeout_count < 100000)) begin

                mmio_read(REG_STATUS, status_value);
                timeout_count = timeout_count + 1;
            end

            if ((status_value[1] !== 1'b1) &&
                (status_value[2] !== 1'b1)) begin
                fail_count = fail_count + 1;
                $display(
                    "[FAIL] Timeout waiting for STATUS.DONE/ERROR after %0d status polls",
                    timeout_count
                );
            end
        end
    endtask

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
                $display("[FAIL] %0s | got=%b expected=%b", name, got, expected);
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
                $display("[FAIL] %0s | got=%0d expected=%0d", name, got, expected);
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
                $display("[FAIL] %0s | got=0x%08h expected=0x%08h", name, got, expected);
            end
        end
    endtask

    initial begin
        #20000000;
        $display("");
        $display("[FAIL] GLOBAL TESTBENCH TIMEOUT");
        $finish;
    end

    initial begin
        pass_count     = 0;
        fail_count     = 0;
        match_count    = 0;
        mismatch_count = 0;

        rst        = 1'b1;
        mmio_addr  = 32'd0;
        mmio_wdata = 32'd0;
        mmio_we    = 1'b0;
        mmio_re    = 1'b0;

        $display("");
        $display("============================================================");
        $display(" Loading REAL MNIST Conv1 Golden Vectors");
        $display("============================================================");

        $readmemh(INPUT_HEX_FILE,  input_words);
        $readmemh(WEIGHT_HEX_FILE, weight_words);
        $readmemh(GOLDEN_HEX_FILE, golden_words);

        $display("Input packed words : %0d", INPUT_WORDS);
        $display("Weight packed words: %0d", WEIGHT_WORDS);
        $display("Golden outputs     : %0d", OUTPUT_VALUES);

        repeat (4) @(posedge clk);
        #1;

        @(negedge clk);
        rst = 1'b0;

        $display("");
        $display("---- TEST 1: CLEAR ----");

        mmio_write(REG_CTRL, CTRL_CLEAR);

        repeat (2) @(posedge clk);
        #1;

        mmio_read(REG_STATUS, read_value);
        check1("STATUS.BUSY after CLEAR",  read_value[0], 1'b0);
        check1("STATUS.DONE after CLEAR",  read_value[1], 1'b0);
        check1("STATUS.ERROR after CLEAR", read_value[2], 1'b0);

        $display("");
        $display("---- TEST 2: Configure REAL Conv1 1x28x28 -> 16x28x28 ----");

        mmio_write(REG_INPUT_H,     INPUT_H);
        mmio_write(REG_INPUT_W,     INPUT_W);
        mmio_write(REG_CIN,         CIN);
        mmio_write(REG_COUT,        COUT);
        mmio_write(REG_KERNEL_SIZE, KERNEL_SIZE);
        mmio_write(REG_STRIDE,      STRIDE);
        mmio_write(REG_PADDING,     PADDING);
        mmio_write(REG_RELU_EN,     RELU_EN);

        mmio_read(REG_OUT_H, read_value);
        check32("OUT_H", read_value, OUT_H);

        mmio_read(REG_OUT_W, read_value);
        check32("OUT_W", read_value, OUT_W);

        $display("");
        $display("---- TEST 3: Load REAL MNIST Activation ----");

        for (i = 0; i < INPUT_WORDS; i = i + 1)
            mmio_write(REG_INPUT_DATA, input_words[i]);

        mmio_read(REG_INPUT_COUNT, read_value);
        check32("MMIO INPUT_COUNT", read_value, INPUT_VALUES);
        check32("Compute input buffer count", dbg_input_buffer_count, INPUT_VALUES);

        $display("");
        $display("---- TEST 4: Load REAL trained Conv1 Weights ----");

        for (i = 0; i < WEIGHT_WORDS; i = i + 1)
            mmio_write(REG_WEIGHT_DATA, weight_words[i]);

        mmio_read(REG_WEIGHT_COUNT, read_value);
        check32("MMIO WEIGHT_COUNT", read_value, WEIGHT_VALUES);
        check32("Compute weight buffer count", dbg_weight_buffer_count, WEIGHT_VALUES);

        $display("");
        $display("---- TEST 5: START REAL Conv1 ----");

        mmio_write(REG_CTRL, CTRL_START);
        wait_for_done_status();

        check1("STATUS.DONE",  status_value[1], 1'b1);
        check1("STATUS.ERROR", status_value[2], 1'b0);
        check1("Compute DONE", dbg_compute_done, 1'b1);
        check1("Compute ERROR", dbg_compute_error, 1'b0);
        check32h("Compute ERROR_CODE", dbg_compute_error_code, 32'h0000_0000);

        mmio_read(REG_OUTPUT_COUNT, read_value);
        check32("MMIO OUTPUT_COUNT", read_value, OUTPUT_VALUES);
        check32("Compute output count", dbg_output_count, OUTPUT_VALUES);

        $display("");
        $display("---- TEST 6: REAL MNIST RTL vs Python Golden ----");
        $display("Comparing %0d INT32 outputs...", OUTPUT_VALUES);

        for (i = 0; i < OUTPUT_VALUES; i = i + 1) begin
            mmio_read(REG_OUTPUT_DATA, read_value);

            if (read_value === golden_words[i]) begin
                match_count = match_count + 1;

                if (i < 8) begin
                    $display(
                        "[MATCH] output[%0d] = %0d",
                        i,
                        $signed(read_value)
                    );
                end
            end
            else begin
                mismatch_count = mismatch_count + 1;

                if (mismatch_count <= 20) begin
                    $display(
                        "[MISMATCH] output[%0d] RTL=%0d PYTHON=%0d (rtl=0x%08h golden=0x%08h)",
                        i,
                        $signed(read_value),
                        $signed(golden_words[i]),
                        read_value,
                        golden_words[i]
                    );
                end
            end
        end

        if (mismatch_count == 0) begin
            pass_count = pass_count + 1;
            $display("[PASS] All REAL Conv1 outputs match Python golden");
        end
        else begin
            fail_count = fail_count + 1;
            $display("[FAIL] REAL Conv1 contains output mismatches");
        end

        check32(
            "Output read index after comparison",
            dbg_output_read_index,
            OUTPUT_VALUES
        );

        $display("");
        $display("---- TEST 7: Final Status ----");

        mmio_read(REG_ERROR_CODE, read_value);
        check32h("MMIO ERROR_CODE", read_value, 32'h0000_0000);

        mmio_read(REG_STATUS, read_value);
        check1("DONE remains latched", read_value[1], 1'b1);
        check1("ERROR remains clear", read_value[2], 1'b0);

        $display("");
        $display("============================================================");
        $display(" REAL MNIST CONV1 VERIFICATION SUMMARY");
        $display("============================================================");
        $display(" TOTAL OUTPUTS = %0d", OUTPUT_VALUES);
        $display(" MATCH         = %0d", match_count);
        $display(" MISMATCH      = %0d", mismatch_count);
        $display("");
        $display(" PASS CHECKS   = %0d", pass_count);
        $display(" FAIL CHECKS   = %0d", fail_count);

        if ((fail_count == 0) &&
            (match_count == OUTPUT_VALUES) &&
            (mismatch_count == 0)) begin
            $display("");
            $display(" RESULT: REAL MNIST CONV1 RTL MATCHES PYTHON GOLDEN");
        end
        else begin
            $display("");
            $display(" RESULT: REAL MNIST CONV1 VERIFICATION FAILED");
        end

        $display(" VCD: tb_conv1_real_golden.vcd");
        $display("============================================================");
        $display("");

        repeat (3) @(posedge clk);
        $finish;
    end

endmodule
