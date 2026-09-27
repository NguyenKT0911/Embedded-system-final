`timescale 1ns/1ps

module tb_weight_buffer;
    // Small buffer for fast unit testing
    localparam integer MAX_VALUES = 8;
    localparam integer ADDR_WIDTH = 3;

    // DUT Inputs
    reg clk;
    reg rst;
    reg clear;

    reg [31:0] write_data;
    reg        write_valid;

    reg                     read_en;
    reg [ADDR_WIDTH-1:0]    read_addr;

    // DUT Outputs
    wire signed [7:0] read_data;
    wire [31:0]       stored_count;
    wire              full;
    wire              overflow_error;

    // Test Counters
    integer pass_count;
    integer fail_count;

    // DUT
    weight_buffer #(
        .MAX_VALUES(MAX_VALUES),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .clear(clear),

        .write_data(write_data),
        .write_valid(write_valid),

        .read_en(read_en),
        .read_addr(read_addr),
        .read_data(read_data),

        .stored_count(stored_count),
        .full(full),
        .overflow_error(overflow_error)
    );

    // 100 MHz Clock
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Waveform Dump
    initial begin
        $dumpfile("tb_weight_buffer.vcd");
        $dumpvars(0, tb_weight_buffer);
    end

    // Write one packed 32-bit word
    task write_word;
        input [31:0] data;
        begin
            @(negedge clk);
            write_data  = data;
            write_valid = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);
            write_valid = 1'b0;
            write_data  = 32'd0;
        end
    endtask

    // Read one INT8 weight
    task read_value;
        input [ADDR_WIDTH-1:0] addr;
        begin
            @(negedge clk);
            read_addr = addr;
            read_en   = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);
            read_en = 1'b0;
        end
    endtask

    // Check 32-bit
    task check32;
        input [8*64-1:0] name;
        input [31:0] got;
        input [31:0] expected;
        begin
            if (got === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s | got=%0d", name, got);
            end
            else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s | got=%0d expected=%0d",
                         name, got, expected);
            end
        end
    endtask

    // Check 1-bit
    task check1;
        input [8*64-1:0] name;
        input got;
        input expected;
        begin
            if (got === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s | got=%b", name, got);
            end
            else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s | got=%b expected=%b",
                         name, got, expected);
            end
        end
    endtask

    // Check signed INT8
    task check8s;
        input [8*64-1:0] name;
        input signed [7:0] got;
        input signed [7:0] expected;
        begin
            if (got === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s | got=%0d", name, got);
            end
            else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s | got=%0d expected=%0d",
                         name, got, expected);
            end
        end
    endtask

    // Main Test Sequence
    initial begin

        pass_count = 0;
        fail_count = 0;

        rst         = 1'b1;
        clear       = 1'b0;
        write_data  = 32'd0;
        write_valid = 1'b0;
        read_en     = 1'b0;
        read_addr   = {ADDR_WIDTH{1'b0}};

        repeat (3) @(posedge clk);
        #1;

        $display("");
        $display("==============================================");
        $display(" Weight Buffer Testbench");
        $display("==============================================");
        $display("");

        // ========================================================
        // TEST 1: Reset
        // ========================================================
        check32("stored_count after reset", stored_count, 32'd0);
        check1 ("full after reset", full, 1'b0);
        check1 ("overflow_error after reset", overflow_error, 1'b0);
        check8s("read_data after reset", read_data, 8'sd0);

        @(negedge clk);
        rst = 1'b0;

        // ========================================================
        // TEST 2: First packed write
        //
        // mem[0] =  10
        // mem[1] = -20 = 0xEC
        // mem[2] =  30
        // mem[3] = -40 = 0xD8
        //
        // write_data = {D8,1E,EC,0A}
        // ========================================================
        $display("");
        $display("---- TEST 2: First Packed Write ----");

        write_word(32'hD81E_EC0A);

        check32("stored_count after first write",
                stored_count, 32'd4);

        check1("full after first write",
               full, 1'b0);

        // ========================================================
        // TEST 3: Read back signed weights
        // ========================================================
        $display("");
        $display("---- TEST 3: Read Back Signed INT8 ----");

        read_value(3'd0);
        check8s("mem[0]", read_data, 8'sd10);

        read_value(3'd1);
        check8s("mem[1]", read_data, -8'sd20);

        read_value(3'd2);
        check8s("mem[2]", read_data, 8'sd30);

        read_value(3'd3);
        check8s("mem[3]", read_data, -8'sd40);

        // ========================================================
        // TEST 4: Second packed write fills buffer
        //
        // mem[4] =  50
        // mem[5] =  60
        // mem[6] = -70 = 0xBA
        // mem[7] =  80
        //
        // write_data = {50,BA,3C,32}
        // ========================================================
        $display("");
        $display("---- TEST 4: Fill Buffer ----");

        write_word(32'h50BA_3C32);

        check32("stored_count when full",
                stored_count, 32'd8);

        check1("full flag",
               full, 1'b1);

        read_value(3'd4);
        check8s("mem[4]", read_data, 8'sd50);

        read_value(3'd6);
        check8s("mem[6]", read_data, -8'sd70);

        read_value(3'd7);
        check8s("mem[7]", read_data, 8'sd80);

        // ========================================================
        // TEST 5: Overflow Protection
        // Third write must not overwrite existing data.
        // ========================================================
        $display("");
        $display("---- TEST 5: Overflow Protection ----");

        write_word(32'h0403_0201);

        check32("stored_count unchanged after overflow",
                stored_count, 32'd8);

        check1("overflow_error set",
               overflow_error, 1'b1);

        check1("full remains set",
               full, 1'b1);

        read_value(3'd7);
        check8s("mem[7] unchanged after overflow",
                read_data, 8'sd80);

        // ========================================================
        // TEST 6: Clear
        // ========================================================
        $display("");
        $display("---- TEST 6: Clear ----");

        @(negedge clk);
        clear = 1'b1;

        @(posedge clk);
        #1;

        @(negedge clk);
        clear = 1'b0;

        check32("stored_count after clear",
                stored_count, 32'd0);

        check1("full after clear",
               full, 1'b0);

        check1("overflow_error after clear",
               overflow_error, 1'b0);

        check8s("read_data after clear",
                read_data, 8'sd0);

        // ========================================================
        // TEST 7: Invalid Read After Clear
        // ========================================================
        $display("");
        $display("---- TEST 7: Invalid Read ----");

        read_value(3'd0);

        check8s("read invalid address returns zero",
                read_data, 8'sd0);

        // Final Summary
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

        $display(" VCD: tb_weight_buffer.vcd");
        $display("==============================================");
        $display("");

        repeat (3) @(posedge clk);
        $finish;
    end

endmodule
