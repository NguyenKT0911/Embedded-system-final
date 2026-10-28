`timescale 1ns/1ps

module tb_firmware_c_full_inference;
    localparam integer CLK_FREQ = 10_000_000;
    localparam integer BAUD_RATE = 1_000_000;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg uart_rx = 1'b1;
    reg [6:0] ui_selected_sample = 7'd0;
    reg ui_run_toggle = 1'b0;
    wire uart_tx;
    wire sd_clk;
    wire sd_cs_n;
    wire sd_mosi;
    wire sd_miso;
    wire [3:0] prediction;
    wire [31:0] sample_id;
    wire prediction_valid;
    wire [799:0] display_image_bits;
    wire display_image_valid;
    wire cpu_trap;
    wire [31:0] trap_pc;
    wire [31:0] trap_cause;
    reg [7:0] uart_byte;
    integer uart_bit;
    integer boot_index;
    integer last_imem;
    integer last_dmem;
    integer boot_errors = 0;
    reg boot_finished = 1'b0;
    reg [31:0] imem_image [0:2047];
    reg [31:0] dmem_image [0:2047];
    integer preview_bit;
    integer preview_count;

    always #50 clk = ~clk;

    initial begin
        wait (boot_finished);
        forever begin
            @(negedge uart_tx);
            repeat (15) @(posedge clk);
            for (uart_bit = 0; uart_bit < 8; uart_bit = uart_bit + 1) begin
                uart_byte[uart_bit] = uart_tx;
                repeat (10) @(posedge clk);
            end
            $display("[UART] %02x", uart_byte);
        end
    end

    always begin
        #250_000_000;
        $display("[PROGRESS] time=%0t pc=%08x cs=%b pred_valid=%b",
                 $time, dut.dbg_pc, sd_cs_n, prediction_valid);
    end

    riscv_ai_soc #(
        .IMEM_WORDS(2048),
        .DMEM_WORDS(2048),
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .clk(clk), .rst(rst), .uart_rx_i(uart_rx), .uart_tx_o(uart_tx),
        .sd_clk_o(sd_clk), .sd_cs_n_o(sd_cs_n),
        .sd_mosi_o(sd_mosi), .sd_miso_i(sd_miso),
        .ui_selected_sample_i(ui_selected_sample),
        .ui_run_toggle_i(ui_run_toggle),
        .ui_hdmi_locked_i(1'b0),
        .reload_request_o(),
        .dbg_pc(), .dbg_instr(), .cpu_trap(cpu_trap),
        .cpu_trap_pc(trap_pc), .cpu_trap_cause(trap_cause),
        .dbg_accel_busy(), .dbg_accel_done(), .dbg_accel_error(),
        .dbg_accel_error_code(), .dbg_input_count(), .dbg_weight_count(),
        .dbg_output_count(), .dbg_output_read_index(), .dbg_uart_rx_valid(),
        .dbg_uart_tx_ready(), .dbg_uart_overrun(), .dbg_uart_framing_error(),
        .dbg_boot_active(), .dbg_boot_error(), .dbg_boot_imem_words(),
        .dbg_boot_dmem_words(),
        .prediction(prediction), .prediction_sample_id(sample_id),
        .prediction_valid(prediction_valid),
        .display_image_bits(display_image_bits),
        .display_image_valid(display_image_valid),
        .stream_out_data(), .stream_out_valid(), .stream_out_ready(1'b1)
    );

    sd_card_spi_model card (
        .cs_n(sd_cs_n), .sclk(sd_clk), .mosi(sd_mosi), .miso(sd_miso)
    );

    task send_uart_byte;
        input [7:0] byte_value;
        integer bit_index;
        begin
            @(negedge clk);
            uart_rx = 1'b0;
            repeat (10) @(posedge clk);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                uart_rx = byte_value[bit_index];
                repeat (10) @(posedge clk);
            end
            uart_rx = 1'b1;
            repeat (10) @(posedge clk);
        end
    endtask

    task receive_uart_byte;
        output [7:0] byte_value;
        integer bit_index;
        begin
            @(negedge uart_tx);
            repeat (15) @(posedge clk);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                byte_value[bit_index] = uart_tx;
                repeat (10) @(posedge clk);
            end
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
        reg [7:0] actual;
        begin
            receive_uart_byte(actual);
            if (actual !== expected) begin
                $display("[FAIL] boot reply got=%02x expected=%02x", actual, expected);
                boot_errors = boot_errors + 1;
            end
        end
    endtask

    task load_firmware_over_uart;
        begin
            $readmemh("firmware_c/build/firmware_c_full.hex", imem_image);
            $readmemh("firmware_c/build/firmware_c_full_dmem.hex", dmem_image);
            last_imem = 0;
            last_dmem = 0;
            for (boot_index = 0; boot_index < 2048; boot_index = boot_index + 1) begin
                if (imem_image[boot_index] != 32'h0000_0013) last_imem = boot_index;
                if (dmem_image[boot_index] != 32'd0) last_dmem = boot_index;
            end

            send_boot_frame(8'h04, 16'd0, 32'd0);
            expect_boot_reply(8'hA5);
            for (boot_index = 0; boot_index <= last_imem; boot_index = boot_index + 1) begin
                send_boot_frame(8'h01, boot_index[15:0], imem_image[boot_index]);
                expect_boot_reply(8'h79);
            end
            for (boot_index = 0; boot_index <= last_dmem; boot_index = boot_index + 1) begin
                send_boot_frame(8'h02, boot_index[15:0], dmem_image[boot_index]);
                expect_boot_reply(8'h79);
            end
            send_boot_frame(8'h03, 16'd0, 32'd0);
            expect_boot_reply(8'h79);
            if (boot_errors != 0)
                $fatal(1, "UART bootload failed errors=%0d", boot_errors);
        end
    endtask

    always @(posedge clk) begin
        if (cpu_trap)
            $fatal(1, "CPU trap pc=%08x cause=%08x", trap_pc, trap_cause);
        if (prediction_valid) begin
            preview_count = 0;
            for (preview_bit = 0; preview_bit < 784; preview_bit = preview_bit + 1)
                if (display_image_bits[preview_bit]) preview_count = preview_count + 1;
            if (!display_image_valid || preview_count != 107 ||
                !display_image_bits[121] || !display_image_bits[660] ||
                display_image_bits[0])
                $fatal(1, "input preview mismatch valid=%0d pixels=%0d",
                       display_image_valid, preview_count);
            if (prediction !== 4'd0 || sample_id !== 32'd100)
                $fatal(1, "prediction mismatch prediction=%0d sample=%0d",
                       prediction, sample_id);
            $display("RESULT: RV32I C FULL CNN FROM SD PASSED prediction=%0d",
                     prediction);
            $finish;
        end
    end

    initial begin
        repeat (8) @(posedge clk);
        rst = 1'b0;
        load_firmware_over_uart();
        boot_finished = 1'b1;
        #10_000_000;
        ui_run_toggle = 1'b1;
    end

    initial begin
        #2_000_000_000;
        #2_000_000_000;
        #2_000_000_000;
        #2_000_000_000;
        #2_000_000_000;
        $fatal(1, "full C firmware inference timeout");
    end
endmodule
