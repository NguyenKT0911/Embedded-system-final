`timescale 1ns/1ps

module tb_data_feeder;

    // ============================================================
    // Small memories for unit/integration testing
    // ============================================================
    localparam integer INPUT_MAX_VALUES  = 16;
    localparam integer WEIGHT_MAX_VALUES = 16;

    localparam integer INPUT_ADDR_WIDTH  = 4;
    localparam integer WEIGHT_ADDR_WIDTH = 4;

    // ============================================================
    // Clock / Reset / Clear
    // ============================================================
    reg clk;
    reg rst;

    reg buffer_clear;
    reg feeder_clear;

    // ============================================================
    // Input Buffer Write Interface
    // ============================================================
    reg [31:0] input_write_data;
    reg        input_write_valid;

    // ============================================================
    // Weight Buffer Write Interface
    // ============================================================
    reg [31:0] weight_write_data;
    reg        weight_write_valid;

    // ============================================================
    // Data Feeder Control
    // ============================================================
    reg start;

    reg [INPUT_ADDR_WIDTH-1:0]  input_base_addr;
    reg [WEIGHT_ADDR_WIDTH-1:0] weight_base_addr;

    // ============================================================
    // Buffer <-> Feeder Read Signals
    // ============================================================
    wire                         input_read_en;
    wire [INPUT_ADDR_WIDTH-1:0]  input_read_addr;
    wire signed [7:0]            input_read_data;

    wire                         weight_read_en;
    wire [WEIGHT_ADDR_WIDTH-1:0] weight_read_addr;
    wire signed [7:0]            weight_read_data;

    // ============================================================
    // Buffer Status
    // ============================================================
    wire [31:0] input_stored_count;
    wire        input_full;
    wire        input_overflow_error;

    wire [31:0] weight_stored_count;
    wire        weight_full;
    wire        weight_overflow_error;

    // ============================================================
    // Data Feeder Outputs
    // ============================================================
    wire        busy;
    wire        data_valid;

    wire [31:0] activation_bus;
    wire [31:0] weight_bus;

    // ============================================================
    // Test Counters
    // ============================================================
    integer pass_count;
    integer fail_count;
    integer timeout_count;

    // ============================================================
    // Input Buffer
    // ============================================================
    input_buffer #(
        .MAX_VALUES(INPUT_MAX_VALUES),
        .ADDR_WIDTH(INPUT_ADDR_WIDTH)
    ) u_input_buffer (
        .clk(clk),
        .rst(rst),
        .clear(buffer_clear),

        .write_data(input_write_data),
        .write_valid(input_write_valid),

        .read_en(input_read_en),
        .read_addr(input_read_addr),
        .read_data(input_read_data),

        .stored_count(input_stored_count),
        .full(input_full),
        .overflow_error(input_overflow_error)
    );

    // ============================================================
    // Weight Buffer
    // ============================================================
    weight_buffer #(
        .MAX_VALUES(WEIGHT_MAX_VALUES),
        .ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) u_weight_buffer (
        .clk(clk),
        .rst(rst),
        .clear(buffer_clear),

        .write_data(weight_write_data),
        .write_valid(weight_write_valid),

        .read_en(weight_read_en),
        .read_addr(weight_read_addr),
        .read_data(weight_read_data),

        .stored_count(weight_stored_count),
        .full(weight_full),
        .overflow_error(weight_overflow_error)
    );

    // ============================================================
    // Data Feeder
    // ============================================================
    data_feeder #(
        .INPUT_ADDR_WIDTH(INPUT_ADDR_WIDTH),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .clear(feeder_clear),

        .start(start),
        .busy(busy),
        .data_valid(data_valid),

        .input_base_addr(input_base_addr),
        .weight_base_addr(weight_base_addr),

        .input_read_en(input_read_en),
        .input_read_addr(input_read_addr),
        .input_read_data(input_read_data),

        .weight_read_en(weight_read_en),
        .weight_read_addr(weight_read_addr),
        .weight_read_data(weight_read_data),

        .activation_bus(activation_bus),
        .weight_bus(weight_bus)
    );

    // ============================================================
    // 100 MHz Clock
    // ============================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ============================================================
    // Waveform Dump
    // ============================================================
    initial begin
        $dumpfile("tb_data_feeder.vcd");
        $dumpvars(0, tb_data_feeder);
    end

    // ============================================================
    // Write one 32-bit packed word into Input Buffer
    // ============================================================
    task write_input_word;
        input [31:0] data;
        begin
            @(negedge clk);

            input_write_data  = data;
            input_write_valid = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);

            input_write_valid = 1'b0;
            input_write_data  = 32'd0;
        end
    endtask

    // ============================================================
    // Write one 32-bit packed word into Weight Buffer
    // ============================================================
    task write_weight_word;
        input [31:0] data;
        begin
            @(negedge clk);

            weight_write_data  = data;
            weight_write_valid = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);

            weight_write_valid = 1'b0;
            weight_write_data  = 32'd0;
        end
    endtask

    // ============================================================
    // Pulse feeder START for one cycle
    // ============================================================
    task pulse_start;
        begin
            @(negedge clk);
            start = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);
            start = 1'b0;
        end
    endtask

    // ============================================================
    // Wait for data_valid with timeout protection
    // ============================================================
    task wait_for_data_valid;
        begin
            timeout_count = 0;

            while ((data_valid !== 1'b1) && (timeout_count < 20)) begin
                @(posedge clk);
                #1;
                timeout_count = timeout_count + 1;
            end

            if (data_valid !== 1'b1) begin
                fail_count = fail_count + 1;
                $display("[FAIL] Timeout waiting for data_valid");
            end
        end
    endtask

    // ============================================================
    // Check 32-bit
    // ============================================================
    task check32;
        input [8*72-1:0] name;
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

    // ============================================================
    // Check 1-bit
    // ============================================================
    task check1;
        input [8*72-1:0] name;
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

    // ============================================================
    // Main Test Sequence
    // ============================================================
    initial begin

        pass_count = 0;
        fail_count = 0;

        rst          = 1'b1;
        buffer_clear = 1'b0;
        feeder_clear = 1'b0;

        input_write_data  = 32'd0;
        input_write_valid = 1'b0;

        weight_write_data  = 32'd0;
        weight_write_valid = 1'b0;

        start = 1'b0;

        input_base_addr  = {INPUT_ADDR_WIDTH{1'b0}};
        weight_base_addr = {WEIGHT_ADDR_WIDTH{1'b0}};

        repeat (3) @(posedge clk);
        #1;

        $display("");
        $display("==============================================");
        $display(" Data Feeder Testbench");
        $display("==============================================");
        $display("");

        // ========================================================
        // TEST 1: Reset
        // ========================================================
        $display("---- TEST 1: Reset ----");

        check1 ("busy after reset", busy, 1'b0);
        check1 ("data_valid after reset", data_valid, 1'b0);
        check32("activation_bus after reset", activation_bus, 32'd0);
        check32("weight_bus after reset", weight_bus, 32'd0);

        @(negedge clk);
        rst = 1'b0;

        // ========================================================
        // TEST 2: Load Buffer Contents
        //
        // Input buffer:
        // addr 0..3 = [1,2,3,4]
        // addr 4..7 = [5,6,7,8]
        //
        // Weight buffer:
        // addr 0..3 = [10,20,30,40]
        // addr 4..7 = [-1,-2,-3,-4]
        // ========================================================
        $display("");
        $display("---- TEST 2: Load Buffers ----");

        write_input_word(32'h0403_0201);
        write_input_word(32'h0807_0605);

        write_weight_word(32'h281E_140A);
        write_weight_word(32'hFCFD_FEFF);

        check32(
            "input_stored_count",
            input_stored_count,
            32'd8
        );

        check32(
            "weight_stored_count",
            weight_stored_count,
            32'd8
        );

        // ========================================================
        // TEST 3: Fetch addresses 0..3
        //
        // Expected activation_bus = {4,3,2,1}
        //                         = 0x04030201
        //
        // Expected weight_bus     = {40,30,20,10}
        //                         = 0x281E140A
        // ========================================================
        $display("");
        $display("---- TEST 3: Fetch First Bundle ----");

        input_base_addr  = 4'd0;
        weight_base_addr = 4'd0;

        pulse_start();

        // After START is accepted, feeder should be busy.
        check1("busy after START", busy, 1'b1);

        wait_for_data_valid();

        check1(
            "data_valid first bundle",
            data_valid,
            1'b1
        );

        check32(
            "activation_bus first bundle",
            activation_bus,
            32'h0403_0201
        );

        check32(
            "weight_bus first bundle",
            weight_bus,
            32'h281E_140A
        );

        // CAPTURE_LAST moves state back to IDLE at the same edge.
        check1(
            "busy low when first bundle ready",
            busy,
            1'b0
        );

        // data_valid must be a one-clock pulse.
        @(posedge clk);
        #1;

        check1(
            "data_valid returns low",
            data_valid,
            1'b0
        );

        // ========================================================
        // TEST 4: Fetch addresses 4..7
        //
        // Input = [5,6,7,8]
        // activation_bus = 0x08070605
        //
        // Weight = [-1,-2,-3,-4]
        // bytes = FF FE FD FC
        // weight_bus = 0xFCFDFEFF
        // ========================================================
        $display("");
        $display("---- TEST 4: Fetch Second Bundle ----");

        input_base_addr  = 4'd4;
        weight_base_addr = 4'd4;

        pulse_start();
        wait_for_data_valid();

        check32(
            "activation_bus second bundle",
            activation_bus,
            32'h0807_0605
        );

        check32(
            "weight_bus signed second bundle",
            weight_bus,
            32'hFCFD_FEFF
        );

        // ========================================================
        // TEST 5: START while BUSY is ignored
        //
        // Begin a normal request at base 0, then assert START again
        // while the FSM is already fetching. The original request
        // must complete normally.
        // ========================================================
        $display("");
        $display("---- TEST 5: START While BUSY ----");

        input_base_addr  = 4'd0;
        weight_base_addr = 4'd0;

        pulse_start();

        check1(
            "busy before repeated START",
            busy,
            1'b1
        );

        // Try another start while feeder is still busy.
        @(negedge clk);
        start = 1'b1;

        @(posedge clk);
        #1;

        @(negedge clk);
        start = 1'b0;

        wait_for_data_valid();

        check32(
            "bundle unchanged by START while busy",
            activation_bus,
            32'h0403_0201
        );

        check32(
            "weight unchanged by START while busy",
            weight_bus,
            32'h281E_140A
        );

        // ========================================================
        // TEST 6: Clear while feeder is active
        //
        // clear must return the feeder to IDLE and erase its packed
        // output registers.
        // ========================================================
        $display("");
        $display("---- TEST 6: Clear During Fetch ----");

        input_base_addr  = 4'd4;
        weight_base_addr = 4'd4;

        pulse_start();

        check1(
            "busy before feeder clear",
            busy,
            1'b1
        );

        @(negedge clk);
        feeder_clear = 1'b1;

        @(posedge clk);
        #1;

        check1(
            "busy after feeder clear",
            busy,
            1'b0
        );

        check1(
            "data_valid after feeder clear",
            data_valid,
            1'b0
        );

        check32(
            "activation_bus cleared",
            activation_bus,
            32'd0
        );

        check32(
            "weight_bus cleared",
            weight_bus,
            32'd0
        );

        @(negedge clk);
        feeder_clear = 1'b0;

        // ========================================================
        // TEST 7: Recovery after Clear
        // ========================================================
        $display("");
        $display("---- TEST 7: Recovery After Clear ----");

        input_base_addr  = 4'd4;
        weight_base_addr = 4'd4;

        pulse_start();
        wait_for_data_valid();

        check32(
            "activation_bus after recovery",
            activation_bus,
            32'h0807_0605
        );

        check32(
            "weight_bus after recovery",
            weight_bus,
            32'hFCFD_FEFF
        );

        // ========================================================
        // Final Summary
        // ========================================================
        $display("");
        $display("==============================================");
        $display(" TEST SUMMARY");
        $display("==============================================");
        $display(" PASS = %0d", pass_count);
        $display(" FAIL = %0d", fail_count);

        if (fail_count == 0)
            $display(" RESULT: ALL TESTS PASSED");
        else
            $display(" RESULT: TESTBENCH FAILED");

        $display(" VCD: tb_data_feeder.vcd");
        $display("==============================================");
        $display("");

        repeat (3) @(posedge clk);
        $finish;
    end

endmodule
