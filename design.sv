// ============================================================
// 1. INSTRUCTION MEMORY
// ============================================================
module instruction_memory(
    input reset,
    input [31:0] address,
    output [31:0] instruction
);
    reg [31:0] mem[1023:0];
    assign instruction = reset ? 32'h00000013 : mem[address[31:2]]; 
endmodule

// ============================================================
// 2. REGISTER FILE (With Reset Init & Internal Write Bypass)
// ============================================================
module register_file (
    input [4:0] register_read_1,
    input [4:0] register_read_2,
    input [4:0] write_register,
    input [31:0] write_data,
    input rwrite,
    input clk,
    input reset,
    output [31:0] read_data_1,
    output [31:0] read_data_2
);
    reg [31:0] registers [31:0];
    integer i;

    // FIX: Internal bypass/forwarding allows same-cycle write-to-read without stale data
    assign read_data_1 = reset ? 32'h00000000 : 
                         (register_read_1 == 5'b00000) ? 32'h00000000 : 
                         (rwrite && (write_register == register_read_1)) ? write_data : 
                         registers[register_read_1];

    assign read_data_2 = reset ? 32'h00000000 : 
                         (register_read_2 == 5'b00000) ? 32'h00000000 : 
                         (rwrite && (write_register == register_read_2)) ? write_data : 
                         registers[register_read_2];

    always @(posedge clk) begin
        if (reset) begin
            // FIX: Initialize all registers to 0 on reset to prevent 'x' propagation
            for (i = 0; i < 32; i = i + 1) begin
                registers[i] <= 32'h00000000;
            end
        end else if (rwrite && (write_register != 5'b00000)) begin
            registers[write_register] <= write_data;
        end
    end
endmodule

// ============================================================
// 3. DATA MEMORY
// ============================================================
module datamemory(
    input [31:0] address,
    input [31:0] write_data,
    input dmread, clk, dmwrite,
    output [31:0] read_data
);
    reg [31:0] memory[1023:0];
    assign read_data = dmread ? memory[address[31:2]] : 32'h00000000; 
  
    always @(posedge clk) begin
        if (dmwrite)
            memory[address[31:2]] <= write_data;
    end
endmodule

// ============================================================
// 4. PROGRAM COUNTER & ADDER
// ============================================================
module program_counter(
    input [31:0] pc_next,
    input clk, reset, halt, stall,
    output reg [31:0] pc
);
    always @(posedge clk) begin 
        if (reset)
            pc <= 32'h00000000; 
        else if (!halt && !stall) // FIX: Freeze PC on Load-Use Stall
            pc <= pc_next;
    end
endmodule

module pc_adder(
    input [31:0] pc_address,
    output [31:0] pc_plus_4
);
    assign pc_plus_4 = pc_address + 32'd4;
endmodule

// ============================================================
// 5. CONTROL UNIT
// ============================================================
module control_unit(
    input [6:0] opcode,
    output reg rwrite,
    output reg memtoreg,
    output reg alusrc,
    output reg branch,
    output reg jump,
    output reg dmwrite,
    output reg dmread,
    output reg halt,
    output reg [1:0] aluop
);
    always @(*) begin
        rwrite   = 1'b0;
        memtoreg = 1'b0;
        alusrc   = 1'b0;
        branch   = 1'b0;
        jump     = 1'b0;
        dmwrite  = 1'b0;
        dmread   = 1'b0;
        aluop    = 2'b00;
        halt     = 1'b0;

        case(opcode)
            7'b0110011: begin // R-type
                rwrite = 1'b1;
                aluop  = 2'b10;
            end
            7'b0010011: begin // I-type
                rwrite = 1'b1;
                alusrc = 1'b1;
                aluop  = 2'b10;
            end
            7'b0000011: begin // LW
                rwrite   = 1'b1;
                memtoreg = 1'b1;
                alusrc   = 1'b1;
                dmread   = 1'b1;
            end
            7'b0100011: begin // SW
                alusrc  = 1'b1;
                dmwrite = 1'b1;
            end
            7'b1100011: begin // BEQ
                branch = 1'b1;
                aluop  = 2'b01;
            end
            7'b1101111: begin // JAL
                rwrite = 1'b1;
                jump   = 1'b1;
                alusrc = 1'b1;
            end
            7'b1111111: halt = 1'b1; // Custom Halt
            default: ;
        endcase
    end
endmodule

// ============================================================
// 6. SIGN EXTENSION
// ============================================================
module sign_extension(
    input [31:0] instruction,
    output reg [31:0] output32
);
    always @(*) begin
        output32 = 32'h00000000; 
        case (instruction[6:0])
            7'b0100011: // S-type
                output32 = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
            7'b0000011, 7'b0010011: // I-type
                output32 = {{20{instruction[31]}}, instruction[31:20]};
            7'b1100011: // B-type
                output32 = {{19{instruction[31]}}, instruction[31], instruction[7], instruction[30:25], instruction[11:8], 1'b0};
            7'b1101111: // J-type
                output32 = {{11{instruction[31]}}, instruction[31], instruction[19:12], instruction[20], instruction[30:21], 1'b0};
            default: output32 = 32'h00000000;
        endcase
    end
endmodule

// ============================================================
// 7. ALU CONTROL & ALU UNIT
// ============================================================
module alu_control(
    input [1:0] aluop,
    input [2:0] func3,
    input func7,
    output reg [3:0] aluoperation
);
    always @(*) begin 
        case(aluop)
            2'b00: aluoperation = 4'b0000; // ADD (for LW/SW/JAL)
            2'b01: aluoperation = 4'b0001; // SUB (for Branch)
            2'b10: begin 
                case(func3)
                    3'b000: aluoperation = (func7) ? 4'b0001 : 4'b0000; // SUB : ADD
                    3'b001: aluoperation = 4'b0010;                      // SLL
                    3'b010: aluoperation = 4'b0011;                      // SLT
                    3'b011: aluoperation = 4'b0100;                      // SLTU
                    3'b100: aluoperation = 4'b0101;                      // XOR
                    3'b101: aluoperation = (func7) ? 4'b0111 : 4'b0110; // SRA : SRL
                    3'b110: aluoperation = 4'b1000;                      // OR
                    3'b111: aluoperation = 4'b1001;                      // AND
                    default: aluoperation = 4'b1111;
                endcase
            end
            default: aluoperation = 4'b1111;
        endcase
    end
endmodule

module alu_unit(
    input [31:0] A,
    input [31:0] B,
    input [3:0] aluoperation,
    output reg zero,
    output reg LT,
    output reg LTU,
    output reg [31:0] result
);
    always @(*) begin
        zero = (A == B);
        LT   = ($signed(A) < $signed(B));
        LTU  = (A < B);
        case(aluoperation)
            4'b0000: result = A + B;
            4'b0001: result = A - B;
            4'b0010: result = A << B[4:0];
            4'b0011: result = LT ? 32'b1 : 32'b0;
            4'b0100: result = LTU ? 32'b1 : 32'b0;
            4'b0101: result = A ^ B;
            4'b0110: result = A >> B[4:0];
            4'b0111: result = $signed(A) >>> B[4:0];
            4'b1000: result = A | B;
            4'b1001: result = A & B;
            default: result = 32'h00000000;
        endcase
    end
endmodule

// ============================================================
// 8. PIPELINED RISC-V TOP-LEVEL MODULE WITH FORWARDING & STALL
// ============================================================
module risc_v_pipelining(
    input clk,
    input reset
);
    // ---------------------------------------------------------
    // DECLARATIONS
    // ---------------------------------------------------------
    // IF Stage
    wire [31:0] pc, pc_next, pc_plus_4, instruction;
    wire branch_taken;
    wire [31:0] target_pc;

    // IF/ID Pipeline Registers
    reg [31:0] id_pc, id_pc_plus_4, id_instruction;

    // ID Stage Wires
    wire id_rwrite, id_memtoreg, id_alusrc, id_branch, id_jump, id_dmwrite, id_dmread, id_halt;
    wire [1:0] id_aluop;
    wire [31:0] id_read_data_1, id_read_data_2, id_immediate;
    wire [4:0] id_rs1, id_rs2;

    // ID/EX Pipeline Registers
    reg [31:0] ex_pc, ex_pc_plus_4, ex_read_data_1, ex_read_data_2, ex_immediate;
    reg [4:0]  ex_rs1, ex_rs2, ex_rd;
    reg [2:0]  ex_func3;
    reg        ex_func7;
    reg        ex_rwrite, ex_memtoreg, ex_alusrc, ex_branch, ex_jump, ex_dmwrite, ex_dmread, ex_halt;
    reg [1:0]  ex_aluop;

    // EX Stage Wires / Forwarding Registers
    wire [3:0]  aluoperation;
    wire [31:0] alu_b_input, alu_result;
    wire        zero, LT, LTU;
    reg         ex_flag;
    reg [1:0]   forward_a, forward_b;
    reg [31:0]  alu_a_input, forward_b_data;

    // EX/MEM Pipeline Registers
    reg [31:0] mem_alu_result, mem_read_data_2, mem_pc_plus_4;
    reg [4:0]  mem_rd;
    reg        mem_rwrite, mem_memtoreg, mem_dmwrite, mem_dmread, mem_jump;

    // MEM Stage Wires
    wire [31:0] mem_read_data;

    // MEM/WB Pipeline Registers
    reg [31:0] wb_read_data, wb_alu_result, wb_pc_plus_4;
    reg [4:0]  wb_rd;
    reg        wb_rwrite, wb_memtoreg, wb_jump;

    // WB Stage Wires
    wire [31:0] wb_write_data;

    // Hazard Signals
    wire stall;

    // ---------------------------------------------------------
    // LOAD-USE HAZARD DETECTION
    // ---------------------------------------------------------
    assign id_rs1 = id_instruction[19:15];
    assign id_rs2 = id_instruction[24:20];

    // FIX: Stall 1 cycle when EX stage is a Load (LW) and destination matches ID source
    assign stall = ex_dmread && (ex_rd != 5'b00000) && ((ex_rd == id_rs1) || (ex_rd == id_rs2));

    // ---------------------------------------------------------
    // IF Stage Logic
    // ---------------------------------------------------------
    // FIX: Guard branch evaluation against 'x' conditions
    assign branch_taken = ((ex_branch === 1'b1) && (ex_flag === 1'b1)) || (ex_jump === 1'b1);
    assign pc_next = (branch_taken === 1'b1) ? target_pc : pc_plus_4;

    program_counter PC_inst (
        .pc_next(pc_next),
        .clk(clk),
        .reset(reset),
        .halt(ex_halt),
        .stall(stall),
        .pc(pc)
    );

    pc_adder PC_Adder_inst (
        .pc_address(pc),
        .pc_plus_4(pc_plus_4)
    );

    instruction_memory IM_inst (
        .reset(reset),
        .address(pc),
        .instruction(instruction)
    );

    // ---------------------------------------------------------
    // IF/ID Pipeline Registers
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (reset || (branch_taken === 1'b1)) begin 
            id_pc          <= 32'h00000000;
            id_pc_plus_4   <= 32'h00000000;
            id_instruction <= 32'h00000013; // NOP
        end else if (!stall) begin // Freeze during Load-Use stall
            id_pc          <= pc;
            id_pc_plus_4   <= pc_plus_4;
            id_instruction <= instruction;
        end
    end

    // ---------------------------------------------------------
    // ID Stage Logic
    // ---------------------------------------------------------
    control_unit CU_inst (
        .opcode(id_instruction[6:0]),
        .rwrite(id_rwrite),
        .memtoreg(id_memtoreg),
        .alusrc(id_alusrc),
        .branch(id_branch),
        .jump(id_jump),
        .dmwrite(id_dmwrite),
        .dmread(id_dmread),
        .halt(id_halt),
        .aluop(id_aluop)
    );

    register_file RF_inst (
        .register_read_1(id_rs1),
        .register_read_2(id_rs2),
        .write_register(wb_rd),
        .write_data(wb_write_data),
        .rwrite(wb_rwrite),
        .clk(clk),
        .reset(reset),
        .read_data_1(id_read_data_1),
        .read_data_2(id_read_data_2)
    );

    sign_extension SE_inst (
        .instruction(id_instruction),
        .output32(id_immediate)
    );

    // ---------------------------------------------------------
    // ID/EX Pipeline Registers
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (reset || (branch_taken === 1'b1) || stall) begin // Insert NOP bubble on stall
            ex_pc          <= 32'h00000000;
            ex_pc_plus_4   <= 32'h00000000;
            ex_read_data_1 <= 32'h00000000;
            ex_read_data_2 <= 32'h00000000;
            ex_immediate   <= 32'h00000000;
            ex_rs1         <= 5'b00000;
            ex_rs2         <= 5'b00000;
            ex_rd          <= 5'b00000;
            ex_func3       <= 3'b000;
            ex_func7       <= 1'b0;
            ex_rwrite      <= 1'b0;
            ex_memtoreg    <= 1'b0;
            ex_alusrc      <= 1'b0;
            ex_branch      <= 1'b0;
            ex_jump        <= 1'b0;
            ex_dmwrite     <= 1'b0;
            ex_dmread      <= 1'b0;
            ex_halt        <= 1'b0;
            ex_aluop       <= 2'b00;
        end else begin
            ex_pc          <= id_pc; 
            ex_pc_plus_4   <= id_pc_plus_4;
            ex_read_data_1 <= id_read_data_1;
            ex_read_data_2 <= id_read_data_2;
            ex_immediate   <= id_immediate;
            ex_rs1         <= id_rs1;
            ex_rs2         <= id_rs2;
            ex_rd          <= id_instruction[11:7];
            ex_func3       <= id_instruction[14:12];
            ex_func7       <= id_instruction[30];
            ex_rwrite      <= id_rwrite;
            ex_memtoreg    <= id_memtoreg;
            ex_alusrc      <= id_alusrc;
            ex_branch      <= id_branch;
            ex_jump        <= id_jump;
            ex_dmwrite     <= id_dmwrite;
            ex_dmread      <= id_dmread;
            ex_halt        <= id_halt;
            ex_aluop       <= id_aluop;
        end
    end

    // ---------------------------------------------------------
    // EX STAGE FORWARDING UNIT
    // ---------------------------------------------------------
    always @(*) begin
        // Forward A (EX/MEM hazard takes priority over MEM/WB hazard)
        if (mem_rwrite && (mem_rd != 5'b00000) && (mem_rd == ex_rs1))
            forward_a = 2'b10;
        else if (wb_rwrite && (wb_rd != 5'b00000) && (wb_rd == ex_rs1))
            forward_a = 2'b01;
        else
            forward_a = 2'b00;

        // Forward B
        if (mem_rwrite && (mem_rd != 5'b00000) && (mem_rd == ex_rs2))
            forward_b = 2'b10;
        else if (wb_rwrite && (wb_rd != 5'b00000) && (wb_rd == ex_rs2))
            forward_b = 2'b01;
        else
            forward_b = 2'b00;
    end

    // Muxes for Forwarded ALU Inputs
    always @(*) begin
        case (forward_a)
            2'b10:   alu_a_input = mem_jump ? mem_pc_plus_4 : (mem_memtoreg ? mem_read_data : mem_alu_result);
            2'b01:   alu_a_input = wb_write_data;
            default: alu_a_input = ex_read_data_1;
        endcase
    end

    always @(*) begin
        case (forward_b)
            2'b10:   forward_b_data = mem_jump ? mem_pc_plus_4 : (mem_memtoreg ? mem_read_data : mem_alu_result);
            2'b01:   forward_b_data = wb_write_data;
            default: forward_b_data = ex_read_data_2;
        endcase
    end

    assign target_pc   = ex_pc + ex_immediate; 
    assign alu_b_input = ex_alusrc ? ex_immediate : forward_b_data;

    alu_control AC_inst (
        .aluop(ex_aluop),
        .func3(ex_func3),
        .func7(ex_func7),
        .aluoperation(aluoperation)
    );

    alu_unit AU_inst (
        .A(alu_a_input),
        .B(alu_b_input),
        .aluoperation(aluoperation),
        .zero(zero),
        .LT(LT),
        .LTU(LTU),
        .result(alu_result)
    );

    always @(*) begin
        case (ex_func3)
            3'b000: ex_flag = zero;   // BEQ
            3'b001: ex_flag = ~zero;  // BNE
            3'b100: ex_flag = LT;     // BLT
            3'b101: ex_flag = ~LT;    // BGE
            3'b110: ex_flag = LTU;    // BLTU
            3'b111: ex_flag = ~LTU;   // BGEU
            default: ex_flag = 1'b0;
        endcase
    end

    // ---------------------------------------------------------
    // EX/MEM Pipeline Registers
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            mem_alu_result  <= 32'h00000000;
            mem_read_data_2 <= 32'h00000000;
            mem_pc_plus_4   <= 32'h00000000;
            mem_rd          <= 5'b00000;
            mem_rwrite      <= 1'b0;
            mem_memtoreg    <= 1'b0;
            mem_dmwrite     <= 1'b0;
            mem_dmread      <= 1'b0;
            mem_jump        <= 1'b0;
        end else begin
            mem_alu_result  <= alu_result;
            mem_read_data_2 <= forward_b_data; // FIX: Forwarded data for Store (SW) instructions
            mem_pc_plus_4   <= ex_pc_plus_4;
            mem_rd          <= ex_rd;
            mem_rwrite      <= ex_rwrite;
            mem_memtoreg    <= ex_memtoreg;
            mem_dmwrite     <= ex_dmwrite;
            mem_dmread      <= ex_dmread;
            mem_jump        <= ex_jump;
        end
    end

    // ---------------------------------------------------------
    // MEM Stage Logic
    // ---------------------------------------------------------
    datamemory DM_inst (
        .address(mem_alu_result),
        .write_data(mem_read_data_2),
        .dmread(mem_dmread),
        .dmwrite(mem_dmwrite),
        .clk(clk),
        .read_data(mem_read_data)
    );

    // ---------------------------------------------------------
    // MEM/WB Pipeline Registers
    // ---------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            wb_read_data  <= 32'h00000000;
            wb_alu_result <= 32'h00000000;
            wb_pc_plus_4  <= 32'h00000000;
            wb_rd         <= 5'b00000;
            wb_rwrite     <= 1'b0;
            wb_memtoreg   <= 1'b0;
            wb_jump       <= 1'b0;
        end else begin
            wb_read_data  <= mem_read_data;
            wb_alu_result <= mem_alu_result;
            wb_pc_plus_4  <= mem_pc_plus_4;
            wb_rd         <= mem_rd;
            wb_rwrite     <= mem_rwrite;
            wb_memtoreg   <= mem_memtoreg;
            wb_jump       <= mem_jump;
        end
    end

    // ---------------------------------------------------------
    // WB Stage Logic
    // ---------------------------------------------------------
    assign wb_write_data = wb_jump ? wb_pc_plus_4 : (wb_memtoreg ? wb_read_data : wb_alu_result);

endmodule