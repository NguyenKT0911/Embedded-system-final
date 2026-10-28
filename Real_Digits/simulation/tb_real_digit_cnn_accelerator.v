`timescale 1ns/1ps

// Testbench mo phong phan cung FPGA: RISC-V SoC + AI Accelerator tren anh thuc te
module tb_real_digit_cnn_accelerator #(
    parameter integer INPUT_H = 28,
    parameter integer INPUT_W = 28,
    parameter integer CIN = 1,
    parameter integer COUT = 16,
    parameter integer INPUT_WORDS = 196,
    parameter integer WEIGHT_WORDS = 36,
    parameter integer OUTPUT_VALUES = 12544,
    parameter INPUT_HEX_FILE = "sim_input.hex",
    parameter WEIGHT_HEX_FILE = "sim_weight.hex",
    parameter OUTPUT_DUMP_FILE = "sim_output.hex",
    parameter TEST_NAME = "CONV"
)(
    input wire unused
);
    localparam integer DMEM_WORDS = 4096;
    localparam integer RESULT_BASE_WORD = 3072;  // byte address 0x3000
    localparam integer MAX_CYCLES = 2000000;

    reg clk;
    reg rst;

    wire [31:0] dbg_pc;
    wire [31:0] dbg_instr;
    wire cpu_trap;
    wire [31:0] cpu_trap_pc;
    wire [31:0] cpu_trap_cause;
    wire dbg_accel_busy;
    wire dbg_accel_done;
    wire dbg_accel_error;
    wire [31:0] dbg_accel_error_code;
    wire [31:0] dbg_input_count;
    wire [31:0] dbg_weight_count;
    wire [31:0] dbg_output_count;
    wire [31:0] dbg_output_read_index;
    wire [31:0] stream_out_data;
    wire stream_out_valid;
    reg stream_out_ready;

    reg [31:0] input_mem [0:INPUT_WORDS-1];
    reg [31:0] weight_mem [0:WEIGHT_WORDS-1];
    reg [31:0] captured_outputs [0:OUTPUT_VALUES-1];

    integer p;
    integer i;
    integer cycles;
    integer input_loop_pc;
    integer weight_loop_pc;
    integer poll_pc;
    integer output_loop_pc;
    integer error_branch_index;
    integer error_pc;
    integer capture_count;
    integer accelerator_busy_cycles;
    integer stream_wait_cycles;
    integer out_file;

    riscv_ai_soc #(
        .IMEM_WORDS(512),
        .DMEM_WORDS(DMEM_WORDS)
    ) dut (
        .clk(clk),
        .rst(rst),
        .uart_rx_i(1'b1),
        .uart_tx_o(),
        .dbg_pc(dbg_pc),
        .dbg_instr(dbg_instr),
        .cpu_trap(cpu_trap),
        .cpu_trap_pc(cpu_trap_pc),
        .cpu_trap_cause(cpu_trap_cause),
        .dbg_accel_busy(dbg_accel_busy),
        .dbg_accel_done(dbg_accel_done),
        .dbg_accel_error(dbg_accel_error),
        .dbg_accel_error_code(dbg_accel_error_code),
        .dbg_input_count(dbg_input_count),
        .dbg_weight_count(dbg_weight_count),
        .dbg_output_count(dbg_output_count),
        .dbg_output_read_index(dbg_output_read_index),
        .dbg_uart_rx_valid(),
        .dbg_uart_tx_ready(),
        .dbg_uart_overrun(),
        .dbg_uart_framing_error(),
        .prediction(),
        .prediction_sample_id(),
        .prediction_valid(),
        .stream_out_data(stream_out_data),
        .stream_out_valid(stream_out_valid),
        .stream_out_ready(stream_out_ready)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (rst) begin
            capture_count <= 0;
            accelerator_busy_cycles <= 0;
            stream_wait_cycles <= 0;
            stream_out_ready <= 1'b0;
        end else begin
            if (!stream_out_valid)
                stream_out_ready <= 1'b0;
            else if (!stream_out_ready)
                stream_out_ready <= 1'b1;
            else
                stream_out_ready <= 1'b0;

            if (stream_out_valid && !stream_out_ready)
                stream_wait_cycles <= stream_wait_cycles + 1;
            if (dbg_accel_busy)
                accelerator_busy_cycles <= accelerator_busy_cycles + 1;
            if (stream_out_valid && stream_out_ready) begin
                if (capture_count < OUTPUT_VALUES)
                    captured_outputs[capture_count] <= stream_out_data;
                capture_count <= capture_count + 1;
            end
        end
    end

    function [31:0] enc_i;
        input [11:0] imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin enc_i = {imm, rs1, funct3, rd, opcode}; end
    endfunction

    function [31:0] enc_s;
        input [11:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        begin
            enc_s = {imm[11:5], rs2, rs1, funct3,
                     imm[4:0], 7'b0100011};
        end
    endfunction

    function [31:0] enc_b;
        input [12:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        begin
            enc_b = {imm[12], imm[10:5], rs2, rs1, funct3,
                     imm[4:1], imm[11], 7'b1100011};
        end
    endfunction

    function [31:0] enc_u;
        input [19:0] imm;
        input [4:0] rd;
        begin enc_u = {imm, rd, 7'b0110111}; end
    endfunction

    function [31:0] enc_j;
        input [20:0] imm;
        input [4:0] rd;
        begin
            enc_j = {imm[20], imm[10:1], imm[11], imm[19:12],
                     rd, 7'b1101111};
        end
    endfunction

    task emit_addi;
        input [4:0] rd;
        input [4:0] rs1;
        input integer value;
        begin
            dut.u_imem.memory[p] = enc_i(value, rs1, 3'b000, rd, 7'b0010011);
            p = p + 1;
        end
    endtask

    task emit_lw;
        input [4:0] rd;
        input [4:0] rs1;
        input integer offset;
        begin
            dut.u_imem.memory[p] = enc_i(offset, rs1, 3'b010, rd, 7'b0000011);
            p = p + 1;
        end
    endtask

    task emit_sw;
        input [4:0] rs2;
        input [4:0] rs1;
        input integer offset;
        begin
            dut.u_imem.memory[p] = enc_s(offset, rs2, rs1, 3'b010);
            p = p + 1;
        end
    endtask

    task build_cpu_program;
        begin
            p = 0;
            dut.u_imem.memory[p] = enc_u(20'h40000, 5'd1); p = p + 1;

            // CLEAR
            emit_addi(5'd8, 5'd0, 2);
            emit_sw(5'd8, 5'd1, 12'h000);

            // Configuration
            emit_addi(5'd8, 5'd0, INPUT_H); emit_sw(5'd8, 5'd1, 12'h008);
            emit_addi(5'd8, 5'd0, INPUT_W); emit_sw(5'd8, 5'd1, 12'h00c);
            emit_addi(5'd8, 5'd0, CIN);     emit_sw(5'd8, 5'd1, 12'h010);
            emit_addi(5'd8, 5'd0, COUT);    emit_sw(5'd8, 5'd1, 12'h014);
            emit_addi(5'd8, 5'd0, 3);       emit_sw(5'd8, 5'd1, 12'h018);
            emit_addi(5'd8, 5'd0, 1);       emit_sw(5'd8, 5'd1, 12'h01c);
            emit_sw(5'd8, 5'd1, 12'h020);
            emit_sw(5'd8, 5'd1, 12'h024);

            // Copy inputs from DMEM[0x0000] to ACCELERATOR INPUT_DATA
            emit_addi(5'd2, 5'd0, 0);
            emit_addi(5'd3, 5'd0, INPUT_WORDS);
            input_loop_pc = p * 4;
            emit_lw(5'd8, 5'd2, 0);
            emit_sw(5'd8, 5'd1, 12'h030);
            emit_addi(5'd2, 5'd2, 4);
            emit_addi(5'd3, 5'd3, -1);
            dut.u_imem.memory[p] = enc_b(input_loop_pc - (p * 4), 5'd0, 5'd3, 3'b001);
            p = p + 1;

            // Copy weights from DMEM[0x1000] to ACCELERATOR WEIGHT_DATA
            dut.u_imem.memory[p] = enc_u(20'h00001, 5'd4); p = p + 1;
            emit_addi(5'd5, 5'd0, WEIGHT_WORDS);
            weight_loop_pc = p * 4;
            emit_lw(5'd8, 5'd4, 0);
            emit_sw(5'd8, 5'd1, 12'h034);
            emit_addi(5'd4, 5'd4, 4);
            emit_addi(5'd5, 5'd5, -1);
            dut.u_imem.memory[p] = enc_b(weight_loop_pc - (p * 4), 5'd0, 5'd5, 3'b001);
            p = p + 1;

            // START & POLL
            emit_addi(5'd8, 5'd0, 1);
            emit_sw(5'd8, 5'd1, 12'h000);
            poll_pc = p * 4;
            emit_lw(5'd9, 5'd1, 12'h004);
            dut.u_imem.memory[p] = enc_i(12'd4, 5'd9, 3'b111, 5'd10, 7'b0010011); p = p + 1;
            error_branch_index = p;
            dut.u_imem.memory[p] = 32'h0000_0013; p = p + 1;
            dut.u_imem.memory[p] = enc_i(12'd2, 5'd9, 3'b111, 5'd10, 7'b0010011); p = p + 1;
            dut.u_imem.memory[p] = enc_b(poll_pc - (p * 4), 5'd0, 5'd10, 3'b000); p = p + 1;

            // Save OUTPUT_COUNT & Drain to Stream
            emit_lw(5'd7, 5'd1, 12'h044);
            dut.u_imem.memory[p] = enc_u(20'h00003, 5'd11); p = p + 1;
            emit_sw(5'd7, 5'd11, 0);
            dut.u_imem.memory[p] = enc_u(20'h00004, 5'd6); p = p + 1;
            output_loop_pc = p * 4;
            emit_lw(5'd8, 5'd1, 12'h038);
            emit_sw(5'd8, 5'd6, 0);
            emit_addi(5'd6, 5'd6, 4);
            emit_addi(5'd7, 5'd7, -1);
            dut.u_imem.memory[p] = enc_b(output_loop_pc - (p * 4), 5'd0, 5'd7, 3'b001); p = p + 1;

            // Success signature at 0x3004
            emit_addi(5'd8, 5'd0, 1);
            emit_sw(5'd8, 5'd11, 4);
            dut.u_imem.memory[p] = enc_j(21'd0, 5'd0); p = p + 1;

            // Error handler
            error_pc = p * 4;
            emit_lw(5'd12, 5'd1, 12'h048);
            dut.u_imem.memory[p] = enc_u(20'h00003, 5'd11); p = p + 1;
            emit_sw(5'd12, 5'd11, 8);
            emit_addi(5'd8, 5'd0, -1);
            emit_sw(5'd8, 5'd11, 4);
            dut.u_imem.memory[p] = enc_j(21'd0, 5'd0); p = p + 1;

            dut.u_imem.memory[error_branch_index] = enc_b(error_pc - (error_branch_index * 4), 5'd0, 5'd10, 3'b001);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        capture_count = 0;
        accelerator_busy_cycles = 0;
        stream_wait_cycles = 0;

        // Avoid a time-zero race with the memory initialization blocks.
        #1;

        $display("[SIM] Loading %0s: %0s and %0s", TEST_NAME, INPUT_HEX_FILE, WEIGHT_HEX_FILE);
        $readmemh(INPUT_HEX_FILE, input_mem);
        $readmemh(WEIGHT_HEX_FILE, weight_mem);

        // Load data into DMEM
        for (i = 0; i < INPUT_WORDS; i = i + 1)
            dut.u_dmem.memory[i] = input_mem[i];
        for (i = 0; i < WEIGHT_WORDS; i = i + 1)
            dut.u_dmem.memory[1024 + i] = weight_mem[i];

        // Build CPU program dynamically
        build_cpu_program();

        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        cycles = 0;
        while ((dut.u_dmem.memory[RESULT_BASE_WORD + 1] === 32'd0) && (cycles < MAX_CYCLES)) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        #1;

        if (cycles >= MAX_CYCLES) begin
            $display("[FAIL] %0s Timeout at PC=0x%08h", TEST_NAME, dbg_pc);
            $finish;
        end

        // Dump captured outputs to file
        out_file = $fopen(OUTPUT_DUMP_FILE, "w");
        for (i = 0; i < capture_count; i = i + 1) begin
            $fwrite(out_file, "%08x\n", captured_outputs[i]);
        end
        $fclose(out_file);

        $display("[SIM_DONE] %0s: Cycles=%0d, Busy=%0d, Outputs=%0d -> Saved to %0s",
                 TEST_NAME, cycles, accelerator_busy_cycles, capture_count, OUTPUT_DUMP_FILE);
        $fflush();
        $finish;
    end
endmodule

// Top modules for Conv1 and Conv2
module tb_sim_conv1;
    tb_real_digit_cnn_accelerator #(
        .INPUT_H(28), .INPUT_W(28), .CIN(1), .COUT(16),
        .INPUT_WORDS(196), .WEIGHT_WORDS(36), .OUTPUT_VALUES(12544),
        .INPUT_HEX_FILE("sim_conv1_input.hex"),
        .WEIGHT_HEX_FILE("sim_conv1_weight.hex"),
        .OUTPUT_DUMP_FILE("sim_conv1_output.hex"),
        .TEST_NAME("CONV1_REAL_DIGIT")
    ) u_checker (.unused(1'b0));
endmodule

module tb_sim_conv2;
    tb_real_digit_cnn_accelerator #(
        .INPUT_H(14), .INPUT_W(14), .CIN(16), .COUT(32),
        .INPUT_WORDS(784), .WEIGHT_WORDS(1152), .OUTPUT_VALUES(6272),
        .INPUT_HEX_FILE("sim_conv2_input.hex"),
        .WEIGHT_HEX_FILE("sim_conv2_weight.hex"),
        .OUTPUT_DUMP_FILE("sim_conv2_output.hex"),
        .TEST_NAME("CONV2_REAL_DIGIT")
    ) u_checker (.unused(1'b0));
endmodule
