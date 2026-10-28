`timescale 1ns/1ps

module soc_instruction_memory #(
    parameter integer WORDS = 256
)(
    input  wire        clk,
    input  wire [31:0] address,
    output reg  [31:0] read_data,
    input  wire        loader_we,
    input  wire [15:0] loader_word_address,
    input  wire [31:0] loader_write_data
);
    localparam integer ADDR_WIDTH = $clog2(WORDS);
    wire [ADDR_WIDTH-1:0] word_index = address[ADDR_WIDTH+1:2];
    reg [31:0] imem [0:WORDS-1];
    initial begin
        read_data = 32'h0000_0013;
    end

    // Keep both ports at the same native address width.  This exact
    // synchronous simple-dual-port shape is required for Gowin to infer
    // BSRAM once UART makes instruction memory writable.
    always @(posedge clk) begin
        if (loader_we)
            imem[loader_word_address[ADDR_WIDTH-1:0]] <= loader_write_data;
        read_data <= imem[word_index];
    end
endmodule

module soc_data_memory #(
    parameter integer WORDS = 4096
)(
    input  wire        clk,
    input  wire [31:0] address,
    input  wire [31:0] write_data,
    input  wire [3:0]  write_strobe,
    input  wire        write_enable,
    input  wire        read_enable,
    output reg  [31:0] read_data,
    input  wire        loader_we,
    input  wire [15:0] loader_word_address,
    input  wire [31:0] loader_write_data
);
    localparam integer ADDR_WIDTH = $clog2(WORDS);
    wire [ADDR_WIDTH-1:0] word_index = address[ADDR_WIDTH+1:2];
    wire [ADDR_WIDTH-1:0] write_index = loader_we
        ? loader_word_address[ADDR_WIDTH-1:0] : word_index;
    wire [31:0] selected_write_data = loader_we ? loader_write_data : write_data;
    wire [3:0] selected_write_strobe = loader_we ? 4'b1111
        : (write_enable ? write_strobe : 4'b0000);
    reg [31:0] dmem [0:WORDS-1];
    initial begin
        read_data = 32'd0;
    end

    always @(posedge clk) begin
        // Registered read matches the native synchronous-read behavior of
        // Gowin block RAM.  The SoC holds a CPU LOAD for one wait-state.
        if (read_enable)
            read_data <= dmem[word_index];

        // UART and CPU share one physical write port.  Expressing the mux
        // before the RAM write lets Gowin infer byte-wide SDPB banks instead
        // of incorrectly expanding the 8 KiB DMEM into flip-flops.
        if (selected_write_strobe[0]) dmem[write_index][7:0]   <= selected_write_data[7:0];
        if (selected_write_strobe[1]) dmem[write_index][15:8]  <= selected_write_data[15:8];
        if (selected_write_strobe[2]) dmem[write_index][23:16] <= selected_write_data[23:16];
        if (selected_write_strobe[3]) dmem[write_index][31:24] <= selected_write_data[31:24];
    end
endmodule

// Minimal SoC integrating the RV32I CPU, local data RAM, and AI accelerator.
//
// Address map:
//   0x0000_0000 .. DMEM_WORDS*4-1 : legacy local RAM alias
//   0x8000_0000 .. +DMEM_WORDS*4-1 : canonical C firmware data RAM
//   0x1000_0000 .. 0x1000_000c    : prediction/display handoff
//   0x2000_0000 .. 0x2000_000c    : UART registers
//   0x3000_0000 .. 0x3000_000c    : SD-card SPI registers
//   0x4000_0000 .. 0x4000_0048    : AI accelerator registers
//   0x4000_1000                    : write-only result stream
//   0x5000_0000                    : selected sample / run-toggle UI
//   0x5000_0008                    : input-image valid control
//   0x5000_0100 .. 0x5000_0160    : 28x28 monochrome input preview
module riscv_ai_soc #(
    parameter [31:0] ACCEL_BASE = 32'h4000_0000,
    parameter [31:0] RESULT_BASE = 32'h1000_0000,
    parameter [31:0] UART_BASE = 32'h2000_0000,
    parameter [31:0] SD_BASE = 32'h3000_0000,
    parameter [31:0] UI_BASE = 32'h5000_0000,
    parameter integer CLK_FREQ = 5_400_000,
    parameter integer BAUD_RATE = 115200,
    parameter integer IMEM_WORDS = 2048,
    parameter integer DMEM_WORDS = 2048
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        uart_rx_i,
    output wire        uart_tx_o,
    output wire        sd_clk_o,
    output wire        sd_cs_n_o,
    output wire        sd_mosi_o,
    input  wire        sd_miso_i,
    input  wire [6:0]  ui_selected_sample_i,
    input  wire        ui_run_toggle_i,
    input  wire        ui_hdmi_locked_i,
    output wire        reload_request_o,

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
    output wire        dbg_uart_rx_valid,
    output wire        dbg_uart_tx_ready,
    output wire        dbg_uart_overrun,
    output wire        dbg_uart_framing_error,
    output wire        dbg_boot_active,
    output wire        dbg_boot_error,
    output wire [15:0] dbg_boot_imem_words,
    output wire [15:0] dbg_boot_dmem_words,
    output wire [6:0]  boot_run_sample,
    output wire        boot_cpu_released,

    // Stable interface for an independently developed HDMI block.
    output wire [3:0]  prediction,
    output wire [31:0] prediction_sample_id,
    output wire        prediction_valid,
    output wire [799:0] display_image_bits,
    output wire         display_image_valid,

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
    reg         imem_fetch_stall;

    wire        boot_imem_we;
    wire [15:0] boot_imem_word_addr;
    wire [31:0] boot_imem_write_data;
    wire        boot_dmem_we;
    wire [15:0] boot_dmem_word_addr;
    wire [31:0] boot_dmem_write_data;
    wire        boot_cpu_release;
    wire        boot_uart_tx;
    wire        runtime_uart_tx;
    wire        runtime_rst = rst || !boot_cpu_release;

    assign uart_tx_o = dbg_boot_active ? boot_uart_tx : runtime_uart_tx;

    uart_bootloader #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .IMEM_WORDS(IMEM_WORDS),
        .DMEM_WORDS(DMEM_WORDS)
    ) u_bootloader (
        .clk(clk),
        .rst(rst),
        .uart_rx_i(uart_rx_i),
        .uart_tx_o(boot_uart_tx),
        .imem_we(boot_imem_we),
        .imem_word_addr(boot_imem_word_addr),
        .imem_write_data(boot_imem_write_data),
        .dmem_we(boot_dmem_we),
        .dmem_word_addr(boot_dmem_word_addr),
        .dmem_write_data(boot_dmem_write_data),
        .cpu_release(boot_cpu_release),
        .run_sample(boot_run_sample),
        .active(dbg_boot_active),
        .error(dbg_boot_error),
        .imem_write_count(dbg_boot_imem_words),
        .dmem_write_count(dbg_boot_dmem_words)
    );
    assign boot_cpu_released = boot_cpu_release;

    wire ram_low_hit = cpu_dmem_addr < DMEM_BYTES;
    wire ram_high_hit = (cpu_dmem_addr >= 32'h8000_0000)
                     && (cpu_dmem_addr < (32'h8000_0000 + DMEM_BYTES));
    wire ram_hit = ram_low_hit || ram_high_hit;
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

    wire [31:0] uart_rdata;
    wire        uart_hit;
    wire        uart_wait;
    wire        uart_word_access = uart_hit &&
                                   (cpu_dmem_size == 2'd2) &&
                                   (cpu_dmem_addr[1:0] == 2'b00);
    wire        uart_re = cpu_dmem_re && uart_word_access;
    wire        uart_we = cpu_dmem_we && uart_word_access &&
                          (cpu_dmem_wstrb == 4'b1111);

    wire [31:0] result_rdata;
    wire        result_hit;
    wire        result_word_access = result_hit &&
                                     (cpu_dmem_size == 2'd2) &&
                                     (cpu_dmem_addr[1:0] == 2'b00);
    wire        result_re = cpu_dmem_re && result_word_access;
    wire        result_we = cpu_dmem_we && result_word_access &&
                            (cpu_dmem_wstrb == 4'b1111);

    wire [31:0] sd_rdata;
    wire        sd_hit;
    wire        sd_wait;
    wire        sd_word_access = sd_hit &&
                                 (cpu_dmem_size == 2'd2) &&
                                 (cpu_dmem_addr[1:0] == 2'b00);
    wire        sd_re = cpu_dmem_re && sd_word_access;
    wire        sd_we = cpu_dmem_we && sd_word_access &&
                        (cpu_dmem_wstrb == 4'b1111);

    wire ui_hit = (cpu_dmem_addr >= UI_BASE) &&
                  (cpu_dmem_addr <= (UI_BASE + 32'h0000_0010));
    wire ui_word_access = ui_hit &&
                          (cpu_dmem_size == 2'd2) &&
                          (cpu_dmem_addr[1:0] == 2'b00);
    wire [31:0] ui_rdata = (cpu_dmem_addr == UI_BASE)
                         ? {25'd0, ui_selected_sample_i}
                         : (cpu_dmem_addr == (UI_BASE + 32'h4))
                         ? {31'd0, ui_run_toggle_i}
                         : (cpu_dmem_addr == (UI_BASE + 32'h8))
                         ? {31'd0, display_image_valid}
                         : {31'd0, ui_hdmi_locked_i};

    wire image_word_hit = (cpu_dmem_addr >= (UI_BASE + 32'h0000_0100)) &&
                          (cpu_dmem_addr <= (UI_BASE + 32'h0000_0160));
    wire image_word_access = image_word_hit &&
                             (cpu_dmem_size == 2'd2) &&
                             (cpu_dmem_addr[1:0] == 2'b00);
    wire image_word_we = cpu_dmem_we && image_word_access &&
                         (cpu_dmem_wstrb == 4'b1111);
    reg [31:0] display_image_words [0:24];
    reg display_image_valid_reg;
    reg reload_request_reg;
    integer display_word_index;
    always @(posedge clk) begin
        if (runtime_rst) begin
            display_image_valid_reg <= 1'b0;
            reload_request_reg <= 1'b0;
            for (display_word_index = 0; display_word_index < 25;
                 display_word_index = display_word_index + 1)
                display_image_words[display_word_index] <= 32'd0;
        end else begin
            if (cpu_dmem_we && ui_word_access &&
                (cpu_dmem_addr == (UI_BASE + 32'h0000_0010)) &&
                (cpu_dmem_wstrb == 4'b1111) && cpu_dmem_wdata[0])
                reload_request_reg <= 1'b1;
            if (cpu_dmem_we && ui_word_access &&
                (cpu_dmem_addr == (UI_BASE + 32'h0000_0008)) &&
                (cpu_dmem_wstrb == 4'b1111))
                display_image_valid_reg <= cpu_dmem_wdata[0];
            if (image_word_we)
                display_image_words[cpu_dmem_addr[6:2]] <= cpu_dmem_wdata;
        end
    end
    assign reload_request_o = reload_request_reg;
    assign display_image_valid = display_image_valid_reg;
    genvar display_word;
    generate
        for (display_word = 0; display_word < 25; display_word = display_word + 1) begin : g_display_image
            assign display_image_bits[display_word * 32 +: 32] =
                display_image_words[display_word];
        end
    endgenerate

    assign stream_out_data  = cpu_dmem_wdata;
    assign stream_out_valid = stream_sink_write;

    // OUTPUT_DATA advances through a registered read pulse in the existing
    // accelerator. Insert one automatic bubble after that read so back-to-back
    // CPU loads cannot observe the same output twice.
    always @(posedge clk) begin
        if (runtime_rst) begin
            output_read_stall <= 1'b0;
            ram_read_ready    <= 1'b0;
            imem_fetch_stall  <= 1'b1;
        end
        else begin
            output_read_stall <= accel_re &&
                                 (cpu_dmem_addr == (ACCEL_BASE + 32'h0000_0038));
            // The instruction ROM is synchronous so it maps to BSRAM.
            // Freeze the CPU every alternate cycle while the next PC word
            // is registered by u_imem.
            if (stream_wait || ram_read_wait || uart_wait)
                imem_fetch_stall <= 1'b0;
            else
                imem_fetch_stall <= ~imem_fetch_stall;

            // First cycle: wait=1 and RAM captures the address.  Second
            // cycle: ready=1, allowing the CPU to consume registered data.
            if (!ram_read_request)
                ram_read_ready <= 1'b0;
            else
                ram_read_ready <= !ram_read_ready;
        end
    end

    assign cpu_dmem_rdata = accel_word_access ? accel_rdata :
                            result_word_access ? result_rdata :
                            uart_word_access  ? uart_rdata  :
                            sd_word_access    ? sd_rdata    :
                            ui_word_access    ? ui_rdata    :
                            image_word_access ? 32'd0       :
                            ram_hit           ? ram_rdata   : 32'd0;

    // Unsupported addresses and sub-word accelerator accesses trap in CPU.
    assign cpu_dmem_fault = (cpu_dmem_re || cpu_dmem_we) &&
                            !(ram_hit || (accel_word_access && accel_hit) ||
                              result_word_access ||
                              uart_word_access || sd_word_access ||
                              ui_word_access ||
                              image_word_access ||
                              stream_sink_write);

    riscv_cpu_bus u_cpu (
        .clk(clk),
        .rst(runtime_rst),
        .stall(output_read_stall || imem_fetch_stall),
        // A wait-state freezes architectural state while keeping the current
        // store request asserted until the result consumer accepts it.
        .dmem_wait(stream_wait || ram_read_wait || uart_wait || sd_wait),
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
        .WORDS(IMEM_WORDS)
    ) u_imem (
        .clk(clk),
        .address(imem_addr),
        .read_data(imem_rdata),
        .loader_we(boot_imem_we),
        .loader_word_address(boot_imem_word_addr),
        .loader_write_data(boot_imem_write_data)
    );

    soc_data_memory #(
        .WORDS(DMEM_WORDS)
    ) u_dmem (
        .clk(clk),
        .address(cpu_dmem_addr),
        .write_data(cpu_dmem_wdata),
        .write_strobe(cpu_dmem_wstrb),
        .write_enable(cpu_dmem_we && ram_hit),
        .read_enable(ram_read_request),
        .read_data(ram_rdata),
        .loader_we(boot_dmem_we),
        .loader_word_address(boot_dmem_word_addr),
        .loader_write_data(boot_dmem_write_data)
    );

    uart_mmio #(
        .BASE_ADDR(UART_BASE),
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_uart (
        .clk(clk),
        .rst(runtime_rst),
        .uart_rx_i(uart_rx_i),
        .uart_tx_o(runtime_uart_tx),
        .bus_addr(cpu_dmem_addr),
        .bus_wdata(cpu_dmem_wdata),
        .bus_re(uart_re),
        .bus_we(uart_we),
        .bus_rdata(uart_rdata),
        .bus_hit(uart_hit),
        .wait_o(uart_wait),
        .dbg_rx_valid(dbg_uart_rx_valid),
        .dbg_tx_ready(dbg_uart_tx_ready),
        .dbg_overrun(dbg_uart_overrun),
        .dbg_framing_error(dbg_uart_framing_error)
    );

    result_mmio #(
        .BASE_ADDR(RESULT_BASE)
    ) u_result (
        .clk(clk),
        .rst(runtime_rst),
        .bus_addr(cpu_dmem_addr),
        .bus_wdata(cpu_dmem_wdata),
        .bus_re(result_re),
        .bus_we(result_we),
        .bus_rdata(result_rdata),
        .bus_hit(result_hit),
        .prediction(prediction),
        .sample_id(prediction_sample_id),
        .prediction_valid(prediction_valid)
    );

    sd_spi_mmio #(
        .BASE_ADDR(SD_BASE)
    ) u_sd_spi (
        .clk(clk),
        .rst(runtime_rst),
        .bus_addr(cpu_dmem_addr),
        .bus_wdata(cpu_dmem_wdata),
        .bus_re(sd_re),
        .bus_we(sd_we),
        .bus_rdata(sd_rdata),
        .bus_hit(sd_hit),
        .wait_o(sd_wait),
        .sd_clk(sd_clk_o),
        .sd_cs_n(sd_cs_n_o),
        .sd_mosi(sd_mosi_o),
        .sd_miso(sd_miso_i)
    );

    wire dbg_core_enable;
    wire dbg_core_clear;
    accelerator_top #(
        .BASE_ADDR(ACCEL_BASE)
    ) u_accelerator (
        .clk(clk),
        .rst(runtime_rst),
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
