`timescale 1ns/1ps

module tb_conv_data_feeder_4x4;

    localparam integer INPUT_MAX_VALUES  = 16;
    localparam integer WEIGHT_MAX_VALUES = 16;
    localparam integer INPUT_ADDR_WIDTH  = 4;
    localparam integer WEIGHT_ADDR_WIDTH = 4;

    reg clk;
    reg rst;
    reg buffer_clear;
    reg feeder_clear;

    reg [31:0] input_write_data;
    reg        input_write_valid;
    reg [31:0] weight_write_data;
    reg        weight_write_valid;

    reg start;

    reg [INPUT_ADDR_WIDTH-1:0] input_addr_0;
    reg [INPUT_ADDR_WIDTH-1:0] input_addr_1;
    reg [INPUT_ADDR_WIDTH-1:0] input_addr_2;
    reg [INPUT_ADDR_WIDTH-1:0] input_addr_3;
    reg [3:0] input_valid_mask;

    reg [WEIGHT_ADDR_WIDTH-1:0] weight_addr_0;
    reg [WEIGHT_ADDR_WIDTH-1:0] weight_addr_1;
    reg [WEIGHT_ADDR_WIDTH-1:0] weight_addr_2;
    reg [WEIGHT_ADDR_WIDTH-1:0] weight_addr_3;
    reg [3:0] weight_valid_mask;

    wire input_read_en;
    wire [INPUT_ADDR_WIDTH-1:0] input_read_addr;
    wire signed [7:0] input_read_data;

    wire weight_read_en;
    wire [WEIGHT_ADDR_WIDTH-1:0] weight_read_addr;
    wire signed [7:0] weight_read_data;

    wire [31:0] input_stored_count;
    wire input_full;
    wire input_overflow_error;

    wire [31:0] weight_stored_count;
    wire weight_full;
    wire weight_overflow_error;

    wire busy;
    wire data_valid;
    wire [31:0] activation_bus;
    wire [31:0] weight_bus;

    integer pass_count;
    integer fail_count;
    integer timeout_count;

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

    conv_data_feeder_4x4 #(
        .INPUT_ADDR_WIDTH(INPUT_ADDR_WIDTH),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .clear(feeder_clear),
        .start(start),
        .busy(busy),
        .data_valid(data_valid),

        .input_addr_0(input_addr_0),
        .input_addr_1(input_addr_1),
        .input_addr_2(input_addr_2),
        .input_addr_3(input_addr_3),
        .input_valid_mask(input_valid_mask),

        .weight_addr_0(weight_addr_0),
        .weight_addr_1(weight_addr_1),
        .weight_addr_2(weight_addr_2),
        .weight_addr_3(weight_addr_3),
        .weight_valid_mask(weight_valid_mask),

        .input_read_en(input_read_en),
        .input_read_addr(input_read_addr),
        .input_read_data(input_read_data),

        .weight_read_en(weight_read_en),
        .weight_read_addr(weight_read_addr),
        .weight_read_data(weight_read_data),

        .activation_bus(activation_bus),
        .weight_bus(weight_bus)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("tb_conv_data_feeder_4x4.vcd");
        $dumpvars(0, tb_conv_data_feeder_4x4);
    end

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

    task check32;
        input [8*80-1:0] name;
        input [31:0] got;
        input [31:0] expected;
        begin
            if (got === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s | got=0x%08h", name, got);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s | got=0x%08h expected=0x%08h", name, got, expected);
            end
        end
    endtask

    task check1;
        input [8*80-1:0] name;
        input got;
        input expected;
        begin
            if (got === expected) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0s | got=%b", name, got);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0s | got=%b expected=%b", name, got, expected);
            end
        end
    endtask

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

        input_addr_0 = 0;
        input_addr_1 = 0;
        input_addr_2 = 0;
        input_addr_3 = 0;
        input_valid_mask = 4'b0000;

        weight_addr_0 = 0;
        weight_addr_1 = 0;
        weight_addr_2 = 0;
        weight_addr_3 = 0;
        weight_valid_mask = 4'b0000;

        repeat (3) @(posedge clk);
        #1;

        $display("");
        $display("==================================================");
        $display(" Conv Data Feeder 4x4 Testbench");
        $display("==================================================");
        $display("");

        // TEST 1: Reset
        check1("busy after reset", busy, 1'b0);
        check1("data_valid after reset", data_valid, 1'b0);
        check32("activation_bus after reset", activation_bus, 32'd0);
        check32("weight_bus after reset", weight_bus, 32'd0);

        @(negedge clk);
        rst = 1'b0;

        // Load 16 input bytes:
        // addr 0..15 = 1,2,3,4,5,6,7,8,9,10,11,12,-1,-2,-3,-4
        write_input_word(32'h0403_0201);
        write_input_word(32'h0807_0605);
        write_input_word(32'h0C0B_0A09);
        write_input_word(32'hFCFD_FEFF);

        // Load 16 weight bytes:
        // addr 0..15 = 10,20,30,40,50,60,70,80,90,100,110,120,-5,-6,-7,-8
        write_weight_word(32'h281E_140A);
        write_weight_word(32'h5046_3C32);
        write_weight_word(32'h786E_645A);
        write_weight_word(32'hF8F9_FAFB);

        check32("input_stored_count", input_stored_count, 32'd16);
        check32("weight_stored_count", weight_stored_count, 32'd16);

        // TEST 2: Non-consecutive addresses
        // input addrs 1,5,9,13 -> [2,6,10,-2]
        // weight addrs 0,4,8,12 -> [10,50,90,-5]
        input_addr_0 = 4'd1;
        input_addr_1 = 4'd5;
        input_addr_2 = 4'd9;
        input_addr_3 = 4'd13;
        input_valid_mask = 4'b1111;

        weight_addr_0 = 4'd0;
        weight_addr_1 = 4'd4;
        weight_addr_2 = 4'd8;
        weight_addr_3 = 4'd12;
        weight_valid_mask = 4'b1111;

        pulse_start();
        check1("busy after non-consecutive START", busy, 1'b1);
        wait_for_data_valid();

        check32("non-consecutive activation bundle", activation_bus, 32'hFE0A_0602);
        check32("non-consecutive weight bundle", weight_bus, 32'hFB5A_320A);
        check1("busy low when bundle ready", busy, 1'b0);

        @(posedge clk);
        #1;
        check1("data_valid one-cycle pulse", data_valid, 1'b0);

        // TEST 3: Input padding mask and weight tail mask
        // input mask 1010 => lanes 0 and 2 forced to zero
        // weight mask 0011 => lanes 2 and 3 forced to zero
        input_addr_0 = 4'd2;
        input_addr_1 = 4'd6;
        input_addr_2 = 4'd10;
        input_addr_3 = 4'd14;
        input_valid_mask = 4'b1010;

        weight_addr_0 = 4'd1;
        weight_addr_1 = 4'd5;
        weight_addr_2 = 4'd9;
        weight_addr_3 = 4'd13;
        weight_valid_mask = 4'b0011;

        pulse_start();
        wait_for_data_valid();

        // input lane bytes = [0,7,0,-3] => FD 00 07 00
        check32("masked activation bundle", activation_bus, 32'hFD00_0700);

        // weight lane bytes = [20,60,0,0] => 00 00 3C 14
        check32("masked weight bundle", weight_bus, 32'h0000_3C14);

        // TEST 4: Snapshot addresses/masks at START
        // Request A is latched, then live inputs are changed to B while busy.
        input_addr_0 = 4'd0;
        input_addr_1 = 4'd4;
        input_addr_2 = 4'd8;
        input_addr_3 = 4'd12;
        input_valid_mask = 4'b1111;

        weight_addr_0 = 4'd3;
        weight_addr_1 = 4'd7;
        weight_addr_2 = 4'd11;
        weight_addr_3 = 4'd15;
        weight_valid_mask = 4'b1111;

        pulse_start();
        check1("busy before changing live addresses", busy, 1'b1);

        // Change live inputs immediately; current request must not change.
        input_addr_0 = 4'd3;
        input_addr_1 = 4'd2;
        input_addr_2 = 4'd1;
        input_addr_3 = 4'd0;
        input_valid_mask = 4'b0001;

        weight_addr_0 = 4'd0;
        weight_addr_1 = 4'd1;
        weight_addr_2 = 4'd2;
        weight_addr_3 = 4'd3;
        weight_valid_mask = 4'b0001;

        wait_for_data_valid();

        // Latched request A:
        // inputs addr 0,4,8,12 => [1,5,9,-1]
        // weights addr 3,7,11,15 => [40,80,120,-8]
        check32("snapshot activation bundle", activation_bus, 32'hFF09_0501);
        check32("snapshot weight bundle", weight_bus, 32'hF878_5028);

        // TEST 5: Signed values explicitly
        input_addr_0 = 4'd12;
        input_addr_1 = 4'd13;
        input_addr_2 = 4'd14;
        input_addr_3 = 4'd15;
        input_valid_mask = 4'b1111;

        weight_addr_0 = 4'd12;
        weight_addr_1 = 4'd13;
        weight_addr_2 = 4'd14;
        weight_addr_3 = 4'd15;
        weight_valid_mask = 4'b1111;

        pulse_start();
        wait_for_data_valid();

        check32("signed activation bundle", activation_bus, 32'hFCFD_FEFF);
        check32("signed weight bundle", weight_bus, 32'hF8F9_FAFB);

        // TEST 6: Clear while active
        input_addr_0 = 4'd1;
        input_addr_1 = 4'd5;
        input_addr_2 = 4'd9;
        input_addr_3 = 4'd13;
        input_valid_mask = 4'b1111;

        weight_addr_0 = 4'd0;
        weight_addr_1 = 4'd4;
        weight_addr_2 = 4'd8;
        weight_addr_3 = 4'd12;
        weight_valid_mask = 4'b1111;

        pulse_start();
        check1("busy before feeder clear", busy, 1'b1);

        @(negedge clk);
        feeder_clear = 1'b1;
        @(posedge clk);
        #1;

        check1("busy after feeder clear", busy, 1'b0);
        check1("data_valid after feeder clear", data_valid, 1'b0);
        check32("activation_bus cleared", activation_bus, 32'd0);
        check32("weight_bus cleared", weight_bus, 32'd0);

        @(negedge clk);
        feeder_clear = 1'b0;

        // TEST 7: Recovery after clear
        input_addr_0 = 4'd1;
        input_addr_1 = 4'd5;
        input_addr_2 = 4'd9;
        input_addr_3 = 4'd13;
        input_valid_mask = 4'b1111;

        weight_addr_0 = 4'd0;
        weight_addr_1 = 4'd4;
        weight_addr_2 = 4'd8;
        weight_addr_3 = 4'd12;
        weight_valid_mask = 4'b1111;

        pulse_start();
        wait_for_data_valid();

        check32("recovery activation bundle", activation_bus, 32'hFE0A_0602);
        check32("recovery weight bundle", weight_bus, 32'hFB5A_320A);

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

        $display(" VCD: tb_conv_data_feeder_4x4.vcd");
        $display("==================================================");
        $display("");

        repeat (3) @(posedge clk);
        $finish;
    end

endmodule
