`timescale 1ns/1ps

// Four-register UART peripheral for the RV32I data bus.
// 0x00 RX_DATA  R  bits[7:0], reading consumes the buffered byte
// 0x04 TX_DATA  W  bits[7:0], the CPU is held with wait_o while TX is busy
// 0x08 STATUS   R  bit0 RX_VALID, bit1 TX_READY, bit2 OVERRUN,
//                  bit3 FRAMING_ERROR
// 0x0c CONTROL  W  bit0 clears sticky error flags, bit1 flushes RX_DATA
module uart_mmio #(
    parameter [31:0] BASE_ADDR = 32'h2000_0000,
    parameter integer CLK_FREQ = 5_400_000,
    parameter integer BAUD_RATE = 115200
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        uart_rx_i,
    output wire        uart_tx_o,
    input  wire [31:0] bus_addr,
    input  wire [31:0] bus_wdata,
    input  wire        bus_re,
    input  wire        bus_we,
    output reg  [31:0] bus_rdata,
    output wire        bus_hit,
    output wire        wait_o,
    output wire        dbg_rx_valid,
    output wire        dbg_tx_ready,
    output wire        dbg_overrun,
    output wire        dbg_framing_error
);
    localparam [31:0] RX_DATA = BASE_ADDR + 32'h00;
    localparam [31:0] TX_DATA = BASE_ADDR + 32'h04;
    localparam [31:0] STATUS  = BASE_ADDR + 32'h08;
    localparam [31:0] CONTROL = BASE_ADDR + 32'h0c;

    wire [7:0] rx_byte;
    wire       rx_byte_valid;
    wire       rx_frame_error;
    reg  [7:0] rx_buffer;
    reg        rx_valid;
    reg        overrun;
    reg        framing_error;

    wire tx_ready;
    wire tx_write  = bus_we && (bus_addr == TX_DATA);
    wire rx_read   = bus_re && (bus_addr == RX_DATA);
    wire ctl_write = bus_we && (bus_addr == CONTROL);

    assign bus_hit = (bus_addr >= BASE_ADDR) &&
                     (bus_addr <= (BASE_ADDR + 32'h0c)) &&
                     (bus_addr[1:0] == 2'b00);
    assign wait_o = tx_write && !tx_ready;

    assign dbg_rx_valid      = rx_valid;
    assign dbg_tx_ready      = tx_ready;
    assign dbg_overrun       = overrun;
    assign dbg_framing_error = framing_error;

    uart_rx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_rx (
        .clk(clk),
        .rst(rst),
        .rx(uart_rx_i),
        .data_out(rx_byte),
        .data_valid(rx_byte_valid),
        .framing_error(rx_frame_error)
    );

    uart_tx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_tx (
        .clk(clk),
        .rst(rst),
        .tx_data(bus_wdata[7:0]),
        .tx_valid(tx_write && tx_ready),
        .tx_ready(tx_ready),
        .tx(uart_tx_o)
    );

    always @(posedge clk) begin
        if (rst) begin
            rx_buffer     <= 8'd0;
            rx_valid      <= 1'b0;
            overrun       <= 1'b0;
            framing_error <= 1'b0;
        end else begin
            if (rx_read)
                rx_valid <= 1'b0;

            if (rx_byte_valid) begin
                if (rx_valid && !rx_read)
                    overrun <= 1'b1;
                else begin
                    rx_buffer <= rx_byte;
                    rx_valid  <= 1'b1;
                end
            end

            if (rx_frame_error)
                framing_error <= 1'b1;

            if (ctl_write) begin
                if (bus_wdata[0]) begin
                    overrun       <= 1'b0;
                    framing_error <= 1'b0;
                end
                if (bus_wdata[1])
                    rx_valid <= 1'b0;
            end
        end
    end

    always @(*) begin
        case (bus_addr)
            RX_DATA: bus_rdata = {24'd0, rx_buffer};
            STATUS:  bus_rdata = {28'd0, framing_error, overrun,
                                  tx_ready, rx_valid};
            default: bus_rdata = 32'd0;
        endcase
    end
endmodule
