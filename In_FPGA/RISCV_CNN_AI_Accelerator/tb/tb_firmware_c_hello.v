`timescale 1ns/1ps

module tb_firmware_c_hello;
    localparam integer CLK_FREQ = 10_000_000;
    localparam integer BAUD_RATE = 1_000_000;
    localparam integer CLKS_PER_BIT = 10;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg uart_rx = 1'b1;
    wire uart_tx;
    wire sd_clk;
    wire sd_cs_n;
    wire sd_mosi;
    reg [7:0] value;
    integer index;
    integer last_imem;
    integer last_dmem;
    integer errors = 0;
    reg [31:0] imem_image [0:2047];
    reg [31:0] dmem_image [0:2047];
    reg [7:0] expected_ready [0:11];
    reg [7:0] expected_pong [0:5];

    always #50 clk = ~clk;

    riscv_ai_soc #(
        .IMEM_WORDS(2048),
        .DMEM_WORDS(2048),
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .clk(clk), .rst(rst), .uart_rx_i(uart_rx), .uart_tx_o(uart_tx),
        .sd_clk_o(sd_clk), .sd_cs_n_o(sd_cs_n),
        .sd_mosi_o(sd_mosi), .sd_miso_i(1'b1),
        .ui_selected_sample_i(7'd0), .ui_run_toggle_i(1'b0),
        .ui_hdmi_locked_i(1'b0),
        .reload_request_o(),
        .dbg_pc(), .dbg_instr(), .cpu_trap(), .cpu_trap_pc(),
        .cpu_trap_cause(), .dbg_accel_busy(), .dbg_accel_done(),
        .dbg_accel_error(), .dbg_accel_error_code(), .dbg_input_count(),
        .dbg_weight_count(), .dbg_output_count(), .dbg_output_read_index(),
        .dbg_uart_rx_valid(), .dbg_uart_tx_ready(), .dbg_uart_overrun(),
        .dbg_uart_framing_error(), .dbg_boot_active(), .dbg_boot_error(),
        .dbg_boot_imem_words(), .dbg_boot_dmem_words(),
        .prediction(), .prediction_sample_id(),
        .prediction_valid(), .display_image_bits(), .display_image_valid(),
        .stream_out_data(), .stream_out_valid(),
        .stream_out_ready(1'b1)
    );

    task send_uart_byte(input [7:0] byte_value);
        integer bit_index;
        begin
            @(negedge clk);
            uart_rx = 1'b0;
            repeat (CLKS_PER_BIT) @(posedge clk);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                uart_rx = byte_value[bit_index];
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            uart_rx = 1'b1;
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    function [31:0] crc32_byte;
        input [31:0] crc_in;
        input [7:0] byte_value;
        integer crc_bit;
        reg [31:0] next;
        begin
            next = crc_in ^ byte_value;
            for (crc_bit = 0; crc_bit < 8; crc_bit = crc_bit + 1)
                next = next[0] ? ((next >> 1) ^ 32'hEDB8_8320) : (next >> 1);
            crc32_byte = next;
        end
    endfunction

    task send_boot_frame;
        input [7:0] command;
        input [15:0] address;
        input [31:0] data;
        reg [31:0] crc;
        reg [31:0] byte_address;
        reg [15:0] payload_length;
        begin
            byte_address = {14'd0, address, 2'b00};
            payload_length = ((command == 8'h01) || (command == 8'h02)) ? 16'd4 : 16'd0;
            crc = crc32_byte(32'hFFFF_FFFF, command);
            crc = crc32_byte(crc, byte_address[7:0]);
            crc = crc32_byte(crc, byte_address[15:8]);
            crc = crc32_byte(crc, byte_address[23:16]);
            crc = crc32_byte(crc, byte_address[31:24]);
            crc = crc32_byte(crc, payload_length[7:0]);
            crc = crc32_byte(crc, payload_length[15:8]);
            if (payload_length != 0) begin
                crc = crc32_byte(crc, data[7:0]);
                crc = crc32_byte(crc, data[15:8]);
                crc = crc32_byte(crc, data[23:16]);
                crc = crc32_byte(crc, data[31:24]);
            end
            crc = crc ^ 32'hFFFF_FFFF;
            send_uart_byte(8'h55);
            send_uart_byte(8'hAA);
            send_uart_byte(command);
            send_uart_byte(byte_address[7:0]);
            send_uart_byte(byte_address[15:8]);
            send_uart_byte(byte_address[23:16]);
            send_uart_byte(byte_address[31:24]);
            send_uart_byte(payload_length[7:0]);
            send_uart_byte(payload_length[15:8]);
            if (payload_length != 0) begin
                send_uart_byte(data[7:0]);
                send_uart_byte(data[15:8]);
                send_uart_byte(data[23:16]);
                send_uart_byte(data[31:24]);
            end
            send_uart_byte(crc[7:0]);
            send_uart_byte(crc[15:8]);
            send_uart_byte(crc[23:16]);
            send_uart_byte(crc[31:24]);
        end
    endtask

    task expect_boot_reply;
        input [7:0] expected;
        begin
            receive_uart_byte(value);
            if (value !== expected) begin
                $display("[FAIL] boot reply got=%02x expected=%02x", value, expected);
                errors = errors + 1;
            end
        end
    endtask

    task load_firmware_over_uart;
        begin
            $readmemh("firmware_c/build/firmware_c_hello.hex", imem_image);
            $readmemh("firmware_c/build/firmware_c_hello_dmem.hex", dmem_image);

            last_imem = 0;
            last_dmem = 0;
            for (index = 0; index < 2048; index = index + 1) begin
                if (imem_image[index] != 32'h0000_0013) last_imem = index;
                if (dmem_image[index] != 32'd0) last_dmem = index;
            end

            send_boot_frame(8'h04, 16'd0, 32'd0);
            expect_boot_reply(8'hA5);
            for (index = 0; index <= last_imem; index = index + 1) begin
                send_boot_frame(8'h01, index[15:0], imem_image[index]);
                expect_boot_reply(8'h79);
            end
            for (index = 0; index <= last_dmem; index = index + 1) begin
                send_boot_frame(8'h02, index[15:0], dmem_image[index]);
                expect_boot_reply(8'h79);
            end
            send_boot_frame(8'h03, 16'd0, 32'd0);
            expect_boot_reply(8'h79);
        end
    endtask

    task receive_uart_byte(output [7:0] byte_value);
        integer bit_index;
        begin
            @(negedge uart_tx);
            repeat (CLKS_PER_BIT + CLKS_PER_BIT/2) @(posedge clk);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                byte_value[bit_index] = uart_tx;
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            if (uart_tx !== 1'b1) errors = errors + 1;
        end
    endtask

    initial begin
        expected_ready[0] = "C"; expected_ready[1] = "_";
        expected_ready[2] = "F"; expected_ready[3] = "W";
        expected_ready[4] = "_"; expected_ready[5] = "R";
        expected_ready[6] = "E"; expected_ready[7] = "A";
        expected_ready[8] = "D"; expected_ready[9] = "Y";
        expected_ready[10] = 8'h0d; expected_ready[11] = 8'h0a;
        expected_pong[0] = "P"; expected_pong[1] = "O";
        expected_pong[2] = "N"; expected_pong[3] = "G";
        expected_pong[4] = 8'h0d; expected_pong[5] = 8'h0a;

        repeat (8) @(posedge clk);
        rst = 1'b0;
        load_firmware_over_uart();
        for (index = 0; index < 12; index = index + 1) begin
            receive_uart_byte(value);
            if (value !== expected_ready[index]) begin
                $display("[FAIL] READY[%0d] got=%02x expected=%02x",
                         index, value, expected_ready[index]);
                errors = errors + 1;
            end
        end
        send_uart_byte("p");
        for (index = 0; index < 6; index = index + 1) begin
            receive_uart_byte(value);
            if (value !== expected_pong[index]) begin
                $display("[FAIL] PONG[%0d] got=%02x expected=%02x",
                         index, value, expected_pong[index]);
                errors = errors + 1;
            end
        end
        if (errors == 0)
            $display("RESULT: RV32I C UART HELLO TEST PASSED");
        else
            $display("RESULT: RV32I C UART HELLO TEST FAILED errors=%0d", errors);
        $finish;
    end

    initial begin
        #2_000_000_000;
        $fatal(1, "C firmware UART test timeout");
    end
endmodule
