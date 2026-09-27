`timescale 1ns/1ps

module tb_output_buffer;

    // ============================================================
    // Small Buffer for Fast Verification
    // ============================================================
    localparam integer MAX_VALUES = 8;
    localparam integer ADDR_WIDTH = 3;

    // ============================================================
    // DUT Inputs
    // ============================================================
    reg clk;
    reg rst;
    reg clear;

    reg [ADDR_WIDTH-1:0] write_addr;
    reg signed [31:0]    write_data;
    reg                  write_valid;

    reg                  read_next;

    // ============================================================
    // DUT Outputs
    // ============================================================
    wire signed [31:0] read_data;

    wire [31:0] stored_count;
    wire [31:0] read_index;

    wire empty;
    wire full;

    wire overflow_error;

    // ============================================================
    // Test Counters
    // ============================================================
    integer pass_count;
    integer fail_count;

    // ============================================================
    // DUT
    // ============================================================
    output_buffer #(
        .MAX_VALUES(MAX_VALUES),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .clear(clear),

        .write_addr(write_addr),
        .write_data(write_data),
        .write_valid(write_valid),

        .read_data(read_data),
        .read_next(read_next),

        .stored_count(stored_count),
        .read_index(read_index),

        .empty(empty),
        .full(full),

        .overflow_error(overflow_error)
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
        $dumpfile("tb_output_buffer.vcd");
        $dumpvars(0, tb_output_buffer);
    end

    // ============================================================
    // Indexed Write Helper
    // ============================================================
    task write_value;
        input [ADDR_WIDTH-1:0] addr;
        input signed [31:0] value;
        begin
            @(negedge clk);

            write_addr  = addr;
            write_data  = value;
            write_valid = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);

            write_valid = 1'b0;
            write_addr  = {ADDR_WIDTH{1'b0}};
            write_data  = 32'sd0;
        end
    endtask

    // ============================================================
    // Advance MMIO Read Pointer
    // ============================================================
    task advance_read;
        begin
            @(negedge clk);
            read_next = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);
            read_next = 1'b0;
        end
    endtask

    // ============================================================
    // Clear Helper
    // ============================================================
    task clear_buffer;
        begin
            @(negedge clk);
            clear = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);
            clear = 1'b0;
        end
    endtask

    // ============================================================
    // Check Helpers
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
                $display("[FAIL] %0s | got=%b expected=%b",
                         name, got, expected);
            end
        end
    endtask

    task check32;
        input [8*72-1:0] name;
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

    task check32s;
        input [8*72-1:0] name;
        input signed [31:0] got;
        input signed [31:0] expected;
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

    // ============================================================
    // Main Test Sequence
    // ============================================================
    initial begin

        pass_count = 0;
        fail_count = 0;

        rst         = 1'b1;
        clear       = 1'b0;

        write_addr  = {ADDR_WIDTH{1'b0}};
        write_data  = 32'sd0;
        write_valid = 1'b0;

        read_next   = 1'b0;

        repeat (3) @(posedge clk);
        #1;

        $display("");
        $display("==================================================");
        $display(" Indexed Output Buffer Testbench");
        $display("==================================================");
        $display("");

        // ========================================================
        // TEST 1: Reset
        // ========================================================
        $display("---- TEST 1: Reset ----");

        check32("stored_count after reset", stored_count, 32'd0);
        check32("read_index after reset", read_index, 32'd0);
        check1 ("empty after reset", empty, 1'b1);
        check1 ("full after reset", full, 1'b0);
        check1 ("overflow_error after reset", overflow_error, 1'b0);
        check32s("read_data after reset", read_data, 32'sd0);

        @(negedge clk);
        rst = 1'b0;

        // ========================================================
        // TEST 2: Indexed Writes Out of Order
        //
        // Write addresses deliberately out of order.
        // After all writes complete, memory should still be readable
        // sequentially in address order 0..7.
        // ========================================================
        $display("");
        $display("---- TEST 2: Indexed Writes Out of Order ----");

        write_value(3'd4,  32'sd400);
        write_value(3'd0,  32'sd100);
        write_value(3'd7, -32'sd800);
        write_value(3'd2,  32'sd300);
        write_value(3'd6,  32'sd700);
        write_value(3'd1, -32'sd200);
        write_value(3'd5, -32'sd600);
        write_value(3'd3, -32'sd400);

        check32("stored_count after 8 indexed writes",
                stored_count, 32'd8);

        check1("full after 8 writes",
               full, 1'b1);

        check1("overflow_error still low",
               overflow_error, 1'b0);

        // ========================================================
        // TEST 3: Sequential MMIO Readback
        //
        // Expected address order:
        //   0 -> 100
        //   1 -> -200
        //   2 -> 300
        //   3 -> -400
        //   4 -> 400
        //   5 -> -600
        //   6 -> 700
        //   7 -> -800
        // ========================================================
        $display("");
        $display("---- TEST 3: Sequential MMIO Readback ----");

        check32s("output[0]", read_data, 32'sd100);

        advance_read();
        check32("read_index = 1", read_index, 32'd1);
        check32s("output[1]", read_data, -32'sd200);

        advance_read();
        check32s("output[2]", read_data, 32'sd300);

        advance_read();
        check32s("output[3]", read_data, -32'sd400);

        advance_read();
        check32s("output[4]", read_data, 32'sd400);

        advance_read();
        check32s("output[5]", read_data, -32'sd600);

        advance_read();
        check32s("output[6]", read_data, 32'sd700);

        advance_read();
        check32s("output[7]", read_data, -32'sd800);

        advance_read();

        check32("read_index after final read",
                read_index, 32'd8);

        check1("empty after all reads",
               empty, 1'b1);

        check32s("read_data when empty",
                 read_data, 32'sd0);

        // ========================================================
        // TEST 4: Read While Empty
        // ========================================================
        $display("");
        $display("---- TEST 4: Read While Empty ----");

        advance_read();

        check32("read_index holds while empty",
                read_index, 32'd8);

        check1("empty remains high",
               empty, 1'b1);

        // ========================================================
        // TEST 5: Overflow Protection
        //
        // Buffer already contains MAX_VALUES successful writes.
        // Another write must be rejected.
        // ========================================================
        $display("");
        $display("---- TEST 5: Overflow Protection ----");

        write_value(3'd0, 32'sd999);

        check32("stored_count unchanged after overflow",
                stored_count, 32'd8);

        check1("overflow_error set",
               overflow_error, 1'b1);

        check1("full remains high",
               full, 1'b1);

        // ========================================================
        // TEST 6: Clear
        // ========================================================
        $display("");
        $display("---- TEST 6: Clear ----");

        clear_buffer();

        check32("stored_count after clear", stored_count, 32'd0);
        check32("read_index after clear", read_index, 32'd0);

        check1("empty after clear", empty, 1'b1);
        check1("full after clear", full, 1'b0);

        check1("overflow_error after clear",
               overflow_error, 1'b0);

        check32s("read_data after clear",
                 read_data, 32'sd0);

        // ========================================================
        // TEST 7: Reuse After Clear
        // ========================================================
        $display("");
        $display("---- TEST 7: Reuse After Clear ----");

        write_value(3'd0, -32'sd123);
        write_value(3'd1,  32'sd456);

        check32("stored_count after reuse",
                stored_count, 32'd2);

        check32s("reuse output[0]",
                 read_data, -32'sd123);

        advance_read();

        check32s("reuse output[1]",
                 read_data, 32'sd456);

        // ========================================================
        // TEST 8: Reset Priority
        // ========================================================
        $display("");
        $display("---- TEST 8: Reset Priority ----");

        @(negedge clk);

        rst         = 1'b1;
        clear       = 1'b1;

        write_addr  = 3'd2;
        write_data  = 32'sd777;
        write_valid = 1'b1;

        read_next   = 1'b1;

        @(posedge clk);
        #1;

        check32("stored_count after priority reset",
                stored_count, 32'd0);

        check32("read_index after priority reset",
                read_index, 32'd0);

        check1("empty after priority reset",
               empty, 1'b1);

        check1("overflow_error after priority reset",
               overflow_error, 1'b0);

        @(negedge clk);

        rst         = 1'b0;
        clear       = 1'b0;

        write_addr  = 3'd0;
        write_data  = 32'sd0;
        write_valid = 1'b0;

        read_next   = 1'b0;

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

        $display(" VCD: tb_output_buffer.vcd");
        $display("==================================================");
        $display("");

        repeat (3) @(posedge clk);
        $finish;
    end

endmodule
