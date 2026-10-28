`timescale 1ns/1ps

// Byte-oriented SPI master for the onboard Tang Nano 20K TF-card socket.
//
// Registers relative to BASE_ADDR:
//   +0x00 CONTROL  RW bit0=CS_N
//   +0x04 STATUS   R  bit0=BUSY, bit1=RX_VALID
//   +0x08 DATA     W starts one 8-bit transfer, R returns RX and clears valid
//   +0x0c DIVIDER  RW SCLK = clk / (2 * (divider + 1))
module sd_spi_mmio #(
    parameter [31:0] BASE_ADDR = 32'h3000_0000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] bus_addr,
    input  wire [31:0] bus_wdata,
    input  wire        bus_re,
    input  wire        bus_we,
    output reg  [31:0] bus_rdata,
    output wire        bus_hit,
    output wire        wait_o,
    output reg         sd_clk,
    output reg         sd_cs_n,
    output reg         sd_mosi,
    input  wire        sd_miso
);
    localparam [31:0] CONTROL = BASE_ADDR + 32'h00;
    localparam [31:0] STATUS  = BASE_ADDR + 32'h04;
    localparam [31:0] DATA    = BASE_ADDR + 32'h08;
    localparam [31:0] DIVIDER = BASE_ADDR + 32'h0c;

    reg [7:0] divider;
    reg [7:0] divider_count;
    reg [7:0] tx_shift;
    reg [7:0] rx_shift;
    reg [7:0] rx_data;
    reg [2:0] bit_count;
    reg       busy;
    reg       rx_valid;

    assign bus_hit = (bus_addr >= BASE_ADDR)
                  && (bus_addr <= BASE_ADDR + 32'h0c)
                  && (bus_addr[1:0] == 2'b00);
    assign wait_o = 1'b0;

    always @(*) begin
        case (bus_addr)
            CONTROL: bus_rdata = {31'd0, sd_cs_n};
            STATUS:  bus_rdata = {30'd0, rx_valid, busy};
            DATA:    bus_rdata = {24'd0, rx_data};
            DIVIDER: bus_rdata = {24'd0, divider};
            default: bus_rdata = 32'd0;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            divider       <= 8'd7;
            divider_count <= 8'd0;
            tx_shift      <= 8'hff;
            rx_shift      <= 8'd0;
            rx_data       <= 8'hff;
            bit_count     <= 3'd0;
            busy          <= 1'b0;
            rx_valid      <= 1'b0;
            sd_clk        <= 1'b0;
            sd_cs_n       <= 1'b1;
            sd_mosi       <= 1'b1;
        end else begin
            if (bus_we && bus_hit && bus_addr == CONTROL)
                sd_cs_n <= bus_wdata[0];

            if (bus_we && bus_hit && bus_addr == DIVIDER && !busy)
                divider <= bus_wdata[7:0];

            if (bus_re && bus_hit && bus_addr == DATA)
                rx_valid <= 1'b0;

            if (bus_we && bus_hit && bus_addr == DATA && !busy) begin
                tx_shift      <= bus_wdata[7:0];
                rx_shift      <= 8'd0;
                bit_count     <= 3'd0;
                divider_count <= divider;
                busy          <= 1'b1;
                rx_valid      <= 1'b0;
                sd_clk        <= 1'b0;
                sd_mosi       <= bus_wdata[7];
            end else if (busy) begin
                if (divider_count != 8'd0) begin
                    divider_count <= divider_count - 1'b1;
                end else begin
                    divider_count <= divider;
                    if (!sd_clk) begin
                        sd_clk   <= 1'b1;
                        rx_shift <= {rx_shift[6:0], sd_miso};
                    end else begin
                        sd_clk <= 1'b0;
                        if (bit_count == 3'd7) begin
                            busy     <= 1'b0;
                            rx_valid <= 1'b1;
                            rx_data  <= rx_shift;
                            sd_mosi  <= 1'b1;
                        end else begin
                            bit_count <= bit_count + 1'b1;
                            tx_shift  <= {tx_shift[6:0], 1'b1};
                            sd_mosi   <= tx_shift[6];
                        end
                    end
                end
            end
        end
    end
endmodule
