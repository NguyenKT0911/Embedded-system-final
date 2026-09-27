`timescale 1ns/1ps

module soc_instruction_memory #(
    parameter integer WORDS = 256,
    parameter INIT_FILE = ""
)(
    input  wire [31:0] address,
    output reg  [31:0] read_data
);
    reg [31:0] memory [0:WORDS-1];
    integer i;

    initial begin
        for (i = 0; i < WORDS; i = i + 1)
            memory[i] = 32'h0000_0013; // addi x0, x0, 0

        if (INIT_FILE != "")
            $readmemh(INIT_FILE, memory);
    end

    // The range check also sends an unknown time-zero/reset PC to the safe
    // NOP path because an X comparison does not take the true branch.
    always @(*) begin
        if (address[31:2] < WORDS)
            read_data = memory[address[31:2]];
        else
            read_data = 32'h0000_0013;
    end
endmodule

module soc_data_memory #(
    parameter integer WORDS = 4096,
    parameter INIT_FILE = ""
)(
    input  wire        clk,
    input  wire [31:0] address,
    input  wire [31:0] write_data,
    input  wire [3:0]  write_strobe,
    input  wire        write_enable,
    input  wire        read_enable,
    output reg  [31:0] read_data
);
    localparam integer ADDR_WIDTH = $clog2(WORDS);
    wire [ADDR_WIDTH-1:0] word_index = address[ADDR_WIDTH+1:2];
    reg [31:0] memory [0:WORDS-1];
    integer i;

    initial begin
        read_data = 32'd0;
        for (i = 0; i < WORDS; i = i + 1)
            memory[i] = 32'd0;
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, memory);
    end

    always @(posedge clk) begin
        // Registered read matches the native synchronous-read behavior of
        // Gowin block RAM.  The SoC holds a CPU LOAD for one wait-state.
        if (read_enable)
            read_data <= memory[word_index];

        if (write_enable) begin
            if (write_strobe[0]) memory[word_index][7:0]   <= write_data[7:0];
            if (write_strobe[1]) memory[word_index][15:8]  <= write_data[15:8];
            if (write_strobe[2]) memory[word_index][23:16] <= write_data[23:16];
            if (write_strobe[3]) memory[word_index][31:24] <= write_data[31:24];
        end
    end
endmodule

// Minimal SoC integrating the RV32I CPU, local data RAM, and AI accelerator.
//
// Address map:
//   0x0000_0000 .. DMEM_WORDS*4-1 : local data RAM
//   0x4000_0000 .. 0x4000_0048    : AI accelerator registers
//   0x4000_1000                    : write-only result stream
module riscv_ai_soc #(
    parameter [31:0] ACCEL_BASE = 32'h4000_0000,
    parameter integer IMEM_WORDS = 256,
    parameter integer DMEM_WORDS = 4096,
    parameter IMEM_INIT_FILE = "",
    parameter DMEM_INIT_FILE = ""
)(
    input  wire        clk,
    input  wire        rst,

    output wire [31:0] dbg_pc,
    output wire [31:0] dbg_instr,
    output wire        cpu_trap,
    output wire [31:0] cpu_trap_pc,
    output wire [31:0] cpu_trap_cause,

    output wire        dbg_accel_busy,
    output wire        dbg_accel_done,
    output wire        dbg_accel_error,
    output wire [31:0] dbg_accel_error_code,
    output wire [31:0] dbg_input_count,
    output wire [31:0] dbg_weight_count,
    output wire [31:0] dbg_output_count,
    output wire [31:0] dbg_output_read_index,

    // Word stream used by firmware to send results without storing the full
    // tensor in local RAM. Address: ACCEL_BASE + 0x1000.
    output wire [31:0] stream_out_data,
    output wire        stream_out_valid,
    input  wire        stream_out_ready
);
    localparam [31:0] DMEM_BYTES = DMEM_WORDS * 4;

    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;

    wire [31:0] cpu_dmem_addr;
    wire [31:0] cpu_dmem_wdata;
    wire [3:0]  cpu_dmem_wstrb;
    wire [1:0]  cpu_dmem_size;
    wire        cpu_dmem_re;
    wire        cpu_dmem_we;
    wire [31:0] cpu_dmem_rdata;
    wire        cpu_dmem_fault;
    reg         output_read_stall;
    reg         ram_read_ready;

    wire ram_hit = cpu_dmem_addr < DMEM_BYTES;
    wire accel_addr_in_window =
        (cpu_dmem_addr >= ACCEL_BASE) &&
        (cpu_dmem_addr <= (ACCEL_BASE + 32'h0000_0048));
    wire accel_word_access = accel_addr_in_window &&
                             (cpu_dmem_size == 2'd2) &&
                             (cpu_dmem_addr[1:0] == 2'b00);

    wire [31:0] ram_rdata;
    wire [31:0] accel_rdata;
    wire        accel_hit;
    wire        accel_re = cpu_dmem_re && accel_word_access;
    wire        accel_we = cpu_dmem_we && accel_word_access &&
                           (cpu_dmem_wstrb == 4'b1111);
    wire stream_sink_addr =
        cpu_dmem_addr == (ACCEL_BASE + 32'h0000_1000);
    wire stream_sink_write = cpu_dmem_we && stream_sink_addr &&
                             (cpu_dmem_size == 2'd2) &&
                             (cpu_dmem_wstrb == 4'b1111);
    wire stream_wait = stream_sink_write && !stream_out_ready;
    wire ram_read_request = cpu_dmem_re && ram_hit;
    wire ram_read_wait = ram_read_request && !ram_read_ready;

    assign stream_out_data  = cpu_dmem_wdata;
    assign stream_out_valid = stream_sink_write;

    // OUTPUT_DATA advances through a registered read pulse in the existing
    // accelerator. Insert one automatic bubble after that read so back-to-back
    // CPU loads cannot observe the same output twice.
    always @(posedge clk) begin
        if (rst) begin
            output_read_stall <= 1'b0;
            ram_read_ready    <= 1'b0;
        end
        else begin
            output_read_stall <= accel_re &&
                                 (cpu_dmem_addr == (ACCEL_BASE + 32'h0000_0038));

            // First cycle: wait=1 and RAM captures the address.  Second
            // cycle: ready=1, allowing the CPU to consume registered data.
            if (!ram_read_request)
                ram_read_ready <= 1'b0;
            else
                ram_read_ready <= !ram_read_ready;
        end
    end

    assign cpu_dmem_rdata = accel_word_access ? accel_rdata :
                            ram_hit           ? ram_rdata   : 32'd0;

    // Unsupported addresses and sub-word accelerator accesses trap in CPU.
    assign cpu_dmem_fault = (cpu_dmem_re || cpu_dmem_we) &&
                            !(ram_hit || (accel_word_access && accel_hit) ||
                              stream_sink_write);

    riscv_cpu_bus u_cpu (
        .clk(clk),
        .rst(rst),
        .stall(output_read_stall),
        // A wait-state freezes architectural state while keeping the current
        // store request asserted until the result consumer accepts it.
        .dmem_wait(stream_wait || ram_read_wait),
        .imem_addr(imem_addr),
        .imem_rdata(imem_rdata),
        .dmem_addr(cpu_dmem_addr),
        .dmem_wdata(cpu_dmem_wdata),
        .dmem_wstrb(cpu_dmem_wstrb),
        .dmem_size(cpu_dmem_size),
        .dmem_re(cpu_dmem_re),
        .dmem_we(cpu_dmem_we),
        .dmem_rdata(cpu_dmem_rdata),
        .dmem_fault(cpu_dmem_fault),
        .dbg_pc(dbg_pc),
        .dbg_instr(dbg_instr),
        .trap(cpu_trap),
        .trap_pc(cpu_trap_pc),
        .trap_cause(cpu_trap_cause)
    );

    soc_instruction_memory #(
        .WORDS(IMEM_WORDS),
        .INIT_FILE(IMEM_INIT_FILE)
    ) u_imem (
        .address(imem_addr),
        .read_data(imem_rdata)
    );

    soc_data_memory #(
        .WORDS(DMEM_WORDS),
        .INIT_FILE(DMEM_INIT_FILE)
    ) u_dmem (
        .clk(clk),
        .address(cpu_dmem_addr),
        .write_data(cpu_dmem_wdata),
        .write_strobe(cpu_dmem_wstrb),
        .write_enable(cpu_dmem_we && ram_hit),
        .read_enable(ram_read_request),
        .read_data(ram_rdata)
    );

    wire dbg_core_enable;
    wire dbg_core_clear;
    accelerator_top #(
        .BASE_ADDR(ACCEL_BASE)
    ) u_accelerator (
        .clk(clk),
        .rst(rst),
        .mmio_addr(cpu_dmem_addr),
        .mmio_wdata(cpu_dmem_wdata),
        .mmio_we(accel_we),
        .mmio_re(accel_re),
        .mmio_rdata(accel_rdata),
        .mmio_hit(accel_hit),
        .dbg_core_enable(dbg_core_enable),
        .dbg_core_clear(dbg_core_clear),
        .dbg_compute_busy(dbg_accel_busy),
        .dbg_compute_done(dbg_accel_done),
        .dbg_compute_error(dbg_accel_error),
        .dbg_compute_error_code(dbg_accel_error_code),
        .dbg_input_buffer_count(dbg_input_count),
        .dbg_weight_buffer_count(dbg_weight_count),
        .dbg_output_count(dbg_output_count),
        .dbg_output_read_index(dbg_output_read_index)
    );

endmodule
