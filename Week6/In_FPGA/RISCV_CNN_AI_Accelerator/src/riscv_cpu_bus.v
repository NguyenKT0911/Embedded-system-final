`timescale 1ns/1ps

// Single-cycle RV32I core with an external instruction port and data bus.
// A slave may extend a transaction with dmem_wait; writes are committed by
// the selected slave on the rising clock edge.
module riscv_cpu_bus (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,
    input  wire        dmem_wait,

    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata,

    output reg  [31:0] dmem_addr,
    output reg  [31:0] dmem_wdata,
    output reg  [3:0]  dmem_wstrb,
    output reg  [1:0]  dmem_size,
    output reg         dmem_re,
    output reg         dmem_we,
    input  wire [31:0] dmem_rdata,
    input  wire        dmem_fault,

    output wire [31:0] dbg_pc,
    output wire [31:0] dbg_instr,
    output reg         trap,
    output reg  [31:0] trap_pc,
    output reg  [31:0] trap_cause
);

    localparam [6:0] OP_LUI    = 7'b0110111;
    localparam [6:0] OP_AUIPC  = 7'b0010111;
    localparam [6:0] OP_JAL    = 7'b1101111;
    localparam [6:0] OP_JALR   = 7'b1100111;
    localparam [6:0] OP_BRANCH = 7'b1100011;
    localparam [6:0] OP_LOAD   = 7'b0000011;
    localparam [6:0] OP_STORE  = 7'b0100011;
    localparam [6:0] OP_IMM    = 7'b0010011;
    localparam [6:0] OP_REG    = 7'b0110011;
    localparam [6:0] OP_FENCE  = 7'b0001111;

    localparam [31:0] CAUSE_ILLEGAL_INSTRUCTION = 32'd2;
    localparam [31:0] CAUSE_LOAD_MISALIGNED     = 32'd4;
    localparam [31:0] CAUSE_LOAD_ACCESS         = 32'd5;
    localparam [31:0] CAUSE_STORE_MISALIGNED    = 32'd6;
    localparam [31:0] CAUSE_STORE_ACCESS        = 32'd7;

    reg [31:0] pc;
    reg [31:0] registers [0:31];

    wire [31:0] instr = imem_rdata;
    wire [6:0]  opcode = instr[6:0];
    wire [4:0]  rd     = instr[11:7];
    wire [2:0]  funct3 = instr[14:12];
    wire [4:0]  rs1    = instr[19:15];
    wire [4:0]  rs2    = instr[24:20];
    wire [6:0]  funct7 = instr[31:25];

    wire [31:0] rs1_data = (rs1 == 5'd0) ? 32'd0 : registers[rs1];
    wire [31:0] rs2_data = (rs2 == 5'd0) ? 32'd0 : registers[rs2];

    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7],
                         instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_u = {instr[31:12], 12'd0};
    wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12],
                         instr[20], instr[30:21], 1'b0};

    reg [31:0] next_pc;
    reg [31:0] writeback_data;
    reg        reg_write;
    reg        illegal_instr;
    reg        mem_misaligned;
    reg        access_is_store;

    wire [31:0] effective_addr = rs1_data +
                                 ((opcode == OP_STORE) ? imm_s : imm_i);
    reg [7:0] selected_byte;
    wire [15:0] selected_half = effective_addr[1]
                              ? dmem_rdata[31:16]
                              : dmem_rdata[15:0];
    reg [31:0] load_value;

    // Select the addressed byte explicitly.  This is equivalent to shifting
    // dmem_rdata, but avoids an implicit 32-to-8-bit truncation warning.
    always @(*) begin
        case (effective_addr[1:0])
            2'd0: selected_byte = dmem_rdata[7:0];
            2'd1: selected_byte = dmem_rdata[15:8];
            2'd2: selected_byte = dmem_rdata[23:16];
            2'd3: selected_byte = dmem_rdata[31:24];
            default: selected_byte = 8'd0;
        endcase
    end

    wire fault_now = illegal_instr | mem_misaligned | dmem_fault;

    assign imem_addr = pc;
    assign dbg_pc = pc;
    assign dbg_instr = instr;

    always @(*) begin
        case (funct3)
            3'b000: load_value = {{24{selected_byte[7]}}, selected_byte};
            3'b001: load_value = {{16{selected_half[15]}}, selected_half};
            3'b010: load_value = dmem_rdata;
            3'b100: load_value = {24'd0, selected_byte};
            3'b101: load_value = {16'd0, selected_half};
            default: load_value = 32'd0;
        endcase
    end

    always @(*) begin
        next_pc        = pc + 32'd4;
        writeback_data = 32'd0;
        reg_write      = 1'b0;
        illegal_instr  = 1'b0;
        mem_misaligned = 1'b0;
        access_is_store = 1'b0;

        dmem_addr  = 32'd0;
        dmem_wdata = 32'd0;
        dmem_wstrb = 4'b0000;
        dmem_size  = 2'd2;
        dmem_re    = 1'b0;
        dmem_we    = 1'b0;

        case (opcode)
            OP_LUI: begin
                reg_write      = 1'b1;
                writeback_data = imm_u;
            end

            OP_AUIPC: begin
                reg_write      = 1'b1;
                writeback_data = pc + imm_u;
            end

            OP_JAL: begin
                reg_write      = 1'b1;
                writeback_data = pc + 32'd4;
                next_pc        = pc + imm_j;
            end

            OP_JALR: begin
                if (funct3 == 3'b000) begin
                    reg_write      = 1'b1;
                    writeback_data = pc + 32'd4;
                    next_pc        = (rs1_data + imm_i) & 32'hffff_fffe;
                end else begin
                    illegal_instr = 1'b1;
                end
            end

            OP_BRANCH: begin
                case (funct3)
                    3'b000: if (rs1_data == rs2_data) next_pc = pc + imm_b;
                    3'b001: if (rs1_data != rs2_data) next_pc = pc + imm_b;
                    3'b100: if ($signed(rs1_data) <  $signed(rs2_data)) next_pc = pc + imm_b;
                    3'b101: if ($signed(rs1_data) >= $signed(rs2_data)) next_pc = pc + imm_b;
                    3'b110: if (rs1_data <  rs2_data) next_pc = pc + imm_b;
                    3'b111: if (rs1_data >= rs2_data) next_pc = pc + imm_b;
                    default: illegal_instr = 1'b1;
                endcase
            end

            OP_LOAD: begin
                dmem_addr = effective_addr;
                reg_write = 1'b1;
                dmem_re   = 1'b1;

                case (funct3)
                    3'b000, 3'b100: dmem_size = 2'd0;
                    3'b001, 3'b101: begin
                        dmem_size = 2'd1;
                        mem_misaligned = effective_addr[0];
                    end
                    3'b010: begin
                        dmem_size = 2'd2;
                        mem_misaligned = |effective_addr[1:0];
                    end
                    default: illegal_instr = 1'b1;
                endcase

                writeback_data = load_value;
            end

            OP_STORE: begin
                dmem_addr = effective_addr;
                dmem_we   = 1'b1;
                access_is_store = 1'b1;

                case (funct3)
                    3'b000: begin
                        dmem_size  = 2'd0;
                        dmem_wstrb = 4'b0001 << effective_addr[1:0];
                        dmem_wdata = {4{rs2_data[7:0]}};
                    end
                    3'b001: begin
                        dmem_size  = 2'd1;
                        mem_misaligned = effective_addr[0];
                        dmem_wstrb = effective_addr[1] ? 4'b1100 : 4'b0011;
                        dmem_wdata = {2{rs2_data[15:0]}};
                    end
                    3'b010: begin
                        dmem_size  = 2'd2;
                        mem_misaligned = |effective_addr[1:0];
                        dmem_wstrb = 4'b1111;
                        dmem_wdata = rs2_data;
                    end
                    default: illegal_instr = 1'b1;
                endcase
            end

            OP_IMM: begin
                reg_write = 1'b1;
                case (funct3)
                    3'b000: writeback_data = rs1_data + imm_i;
                    3'b010: writeback_data = ($signed(rs1_data) < $signed(imm_i));
                    3'b011: writeback_data = (rs1_data < imm_i);
                    3'b100: writeback_data = rs1_data ^ imm_i;
                    3'b110: writeback_data = rs1_data | imm_i;
                    3'b111: writeback_data = rs1_data & imm_i;
                    3'b001: begin
                        if (funct7 == 7'b0000000)
                            writeback_data = rs1_data << instr[24:20];
                        else
                            illegal_instr = 1'b1;
                    end
                    3'b101: begin
                        if (funct7 == 7'b0000000)
                            writeback_data = rs1_data >> instr[24:20];
                        else if (funct7 == 7'b0100000)
                            writeback_data = $signed(rs1_data) >>> instr[24:20];
                        else
                            illegal_instr = 1'b1;
                    end
                    default: illegal_instr = 1'b1;
                endcase
            end

            OP_REG: begin
                reg_write = 1'b1;
                case (funct3)
                    3'b000: begin
                        if (funct7 == 7'b0000000)
                            writeback_data = rs1_data + rs2_data;
                        else if (funct7 == 7'b0100000)
                            writeback_data = rs1_data - rs2_data;
                        else
                            illegal_instr = 1'b1;
                    end
                    3'b001: begin
                        if (funct7 == 7'b0000000) writeback_data = rs1_data << rs2_data[4:0];
                        else illegal_instr = 1'b1;
                    end
                    3'b010: begin
                        if (funct7 == 7'b0000000) writeback_data = ($signed(rs1_data) < $signed(rs2_data));
                        else illegal_instr = 1'b1;
                    end
                    3'b011: begin
                        if (funct7 == 7'b0000000) writeback_data = (rs1_data < rs2_data);
                        else illegal_instr = 1'b1;
                    end
                    3'b100: begin
                        if (funct7 == 7'b0000000) writeback_data = rs1_data ^ rs2_data;
                        else illegal_instr = 1'b1;
                    end
                    3'b101: begin
                        if (funct7 == 7'b0000000)
                            writeback_data = rs1_data >> rs2_data[4:0];
                        else if (funct7 == 7'b0100000)
                            writeback_data = $signed(rs1_data) >>> rs2_data[4:0];
                        else
                            illegal_instr = 1'b1;
                    end
                    3'b110: begin
                        if (funct7 == 7'b0000000) writeback_data = rs1_data | rs2_data;
                        else illegal_instr = 1'b1;
                    end
                    3'b111: begin
                        if (funct7 == 7'b0000000) writeback_data = rs1_data & rs2_data;
                        else illegal_instr = 1'b1;
                    end
                    default: illegal_instr = 1'b1;
                endcase
            end

            // FENCE/FENCE.I are no-ops in this single-core, uncached design.
            OP_FENCE: begin
                if ((funct3 != 3'b000) && (funct3 != 3'b001))
                    illegal_instr = 1'b1;
            end

            default: illegal_instr = 1'b1;
        endcase

        // Do not let an invalid or misaligned instruction create a bus
        // transaction on the same edge that records the trap.
        if (illegal_instr || mem_misaligned || stall) begin
            dmem_re = 1'b0;
            dmem_we = 1'b0;
            reg_write = 1'b0;
        end
    end

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            pc         <= 32'd0;
            trap       <= 1'b0;
            trap_pc    <= 32'd0;
            trap_cause <= 32'd0;
            for (i = 0; i < 32; i = i + 1)
                registers[i] <= 32'd0;
        end else if (!trap && !stall && !dmem_wait) begin
            if (fault_now) begin
                trap    <= 1'b1;
                trap_pc <= pc;

                if (illegal_instr)
                    trap_cause <= CAUSE_ILLEGAL_INSTRUCTION;
                else if (mem_misaligned)
                    trap_cause <= access_is_store ? CAUSE_STORE_MISALIGNED
                                                  : CAUSE_LOAD_MISALIGNED;
                else
                    trap_cause <= access_is_store ? CAUSE_STORE_ACCESS
                                                  : CAUSE_LOAD_ACCESS;
            end else begin
                pc <= next_pc;
                if (reg_write && (rd != 5'd0))
                    registers[rd] <= writeback_data;
            end
        end
    end

endmodule
