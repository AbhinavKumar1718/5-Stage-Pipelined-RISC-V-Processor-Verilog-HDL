// ============================================================================
// 1. Instruction Memory
// ============================================================================
module instruction_memory(
    input reset,
    input [31:0] address,
    output [31:0] instruction
);
    reg [31:0] mem[1023:0];
    assign instruction = reset ? 32'h00000000 : mem[address[31:2]];
endmodule

// ============================================================================
// 2. Data Memory
// ============================================================================
module datamemory(
    input [31:0] address,
    input [31:0] write_data,
    input mem_read, clk, mem_write,
    output [31:0] read_data
);
    reg [31:0] memory[1023:0];
    assign read_data = mem_read ? memory[address[31:2]] : 32'h00000000;

    always @(posedge clk) begin
        if (mem_write)
            memory[address[31:2]] <= write_data;
    end
endmodule

// ============================================================================
// 3. Program Counter
// ============================================================================
module program_counter(
    input [31:0] pc_next,
    input clk, reset, halt,
    output reg [31:0] pc
);
    always @(posedge clk) begin
        if (reset)
            pc <= 32'h00000000;
        else if (!halt)
            pc <= pc_next;
    end
endmodule

// ============================================================================
// 4. PC Adder
// ============================================================================
module pc_adder(
    input [31:0] pc_address,
    output [31:0] pc_plus_4
);
    assign pc_plus_4 = pc_address + 32'd4;
endmodule

// ============================================================================
// 5. Register File
// ============================================================================
module register_file (
    input [4:0] register_read_1,
    input [4:0] register_read_2,
    input [4:0] write_register,
    input [31:0] write_data,
    input reg_write,
    input clk,
    input reset,
    output [31:0] read_data_1,
    output [31:0] read_data_2
);
    reg [31:0] registers [31:0];

    assign read_data_1 = reset ? 32'h00000000 :
                         (register_read_1 == 5'b00000) ? 32'h00000000 :
                         registers[register_read_1];

    assign read_data_2 = reset ? 32'h00000000 :
                         (register_read_2 == 5'b00000) ? 32'h00000000 :
                         registers[register_read_2];
    integer i;

    always @(posedge clk) begin
      if (reset) begin
          for (i = 0; i < 32; i = i + 1) begin
             registers[i] <= 32'h00000000;
        end
      end
        else if(reg_write && (write_register != 5'b00000)) begin
            registers[write_register] <= write_data;
        end
    end
endmodule

// ============================================================================
// 6. ALU Unit
// ============================================================================
module alu_unit(
    input [31:0] A,
    input [31:0] B,
    input [3:0] ALU_operation,
    output reg zero,
    output reg LT,
    output reg LTU,
    output reg [31:0] result
);
    always @(*) begin
        zero = (A == B);
        LT   = ($signed(A) < $signed(B));
        LTU  = (A < B);

        case (ALU_operation)
            4'b0000: result = A + B;                       // ADD
            4'b0001: result = A - B;                       // SUB
            4'b0010: result = A << B[4:0];                // SLL
            4'b0011: result = LT  ? 32'b1 : 32'b0;        // SLT
            4'b0100: result = LTU ? 32'b1 : 32'b0;        // SLTU
            4'b0101: result = A ^ B;                       // XOR
            4'b0110: result = A >> B[4:0];                // SRL
            4'b0111: result = $signed(A) >>> B[4:0];       // SRA
            4'b1000: result = A | B;                       // OR
            4'b1001: result = A & B;                       // AND
            default: result = 32'h00000000;
        endcase
    end
endmodule

// ============================================================================
// 7. Sign Extension
// ============================================================================
module sign_extension(
    input [31:0] instruction,
    output reg [31:0] output32
);
    always @(*) begin
        case (instruction[6:0])
            // S-type (Store)
            7'b0100011: begin
                output32 = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
            end

            // I-type (Load, ALU Immediates)
            7'b0000011,
            7'b0010011: begin
                output32 = {{20{instruction[31]}}, instruction[31:20]};
            end

            // B-type (Branch)
            7'b1100011: begin
                output32 = {{19{instruction[31]}}, instruction[31], instruction[7], instruction[30:25], instruction[11:8], 1'b0};
            end

            // J-type (JAL)
            7'b1101111: begin
                output32 = {{11{instruction[31]}}, instruction[31], instruction[19:12], instruction[20], instruction[30:21], 1'b0};
            end

            default: output32 = 32'h00000000;
        endcase
    end
endmodule

// ============================================================================
// 8. Instruction Fetch with Control Transfer
// ============================================================================
module instruction_fetch_with_control_transfer(
    input clk, reset, branch, halt, jump, flag,
    input [31:0] offset,
    output [31:0] instruction,
    output [31:0] PC_plus_4
);
    wire [31:0] PC_address;
    wire [31:0] Actual_PC_address;
    wire [31:0] BTA, JTA;
    wire branch_taken;

    program_counter PC (
        .pc_next(Actual_PC_address),
        .clk(clk),
        .halt(halt),
        .reset(reset),
        .pc(PC_address)
    );

    pc_adder ADD (
        .pc_address(PC_address),
        .pc_plus_4(PC_plus_4)
    );

    instruction_memory IMEM (
        .reset(reset),
        .address(PC_address),
        .instruction(instruction)
    );

    assign BTA = PC_address + offset;
    assign JTA = PC_address + offset;

    assign branch_taken = branch & flag;

    assign Actual_PC_address = jump         ? JTA :
                               branch_taken ? BTA :
                                              PC_plus_4;
endmodule

// ============================================================================
// 9. Single Cycle Datapath (SCDP)
// ============================================================================
module SCDP_without_control_unit(
    input clk, reset, RegWrite, ALUsrc, memRead, memWrite, halt,
    input MemToReg, branch, jump,
    input [3:0] ALUoperation,
    output func7,
    output [6:0] opcode,
    output [2:0] func
);
    reg flag;
    wire zero, LT, LTU;
    wire [31:0] instruction, read_data_1, read_data_2, ALU_operand2;
    wire [31:0] operand_32, Mem_or_ALU, AluData, MemData, PC_plus_4;

    instruction_fetch_with_control_transfer IFCT(
        .reset(reset),
        .clk(clk),
        .halt(halt),
        .flag(flag),
        .branch(branch),
        .jump(jump),
        .offset(operand_32),
        .instruction(instruction),
        .PC_plus_4(PC_plus_4)
    );

    assign opcode = instruction[6:0];
    assign func   = instruction[14:12];
    assign func7  = instruction[30];

    register_file RF(
        .register_read_1(instruction[19:15]),
        .register_read_2(instruction[24:20]),
        .write_register(instruction[11:7]),
        .write_data(Mem_or_ALU),
        .reg_write(RegWrite),
        .clk(clk),
        .reset(reset),
        .read_data_1(read_data_1),
        .read_data_2(read_data_2)
    );

    sign_extension SE(
        .instruction(instruction),
        .output32(operand_32)
    );

    assign ALU_operand2 = ALUsrc ? operand_32 : read_data_2;

    alu_unit AU(
        .A(read_data_1),
        .B(ALU_operand2),
        .ALU_operation(ALUoperation),
        .zero(zero),
        .LT(LT),
        .LTU(LTU),
        .result(AluData)
    );

    always @(*) begin
        case (func)
            3'b000: flag = zero;   // BEQ
            3'b001: flag = !zero;  // BNE
            3'b100: flag = LT;     // BLT
            3'b101: flag = !LT;    // BGE
            3'b110: flag = LTU;    // BLTU
            3'b111: flag = !LTU;   // BGEU
            default: flag = 1'b0;
        endcase
    end

    datamemory DM(
        .address(AluData),
        .write_data(read_data_2),
        .mem_read(memRead),
        .clk(clk),
        .mem_write(memWrite),
        .read_data(MemData)
    );

    assign Mem_or_ALU = jump ? PC_plus_4 : (MemToReg ? MemData : AluData);
endmodule

// ============================================================================
// 10. Main Control Unit
// ============================================================================
module control_unit_datapath(
    input [6:0] opcode,
    output reg RegWrite,
    output reg MemToReg,
    output reg ALUsrc,
    output reg branch,
    output reg jump,
    output reg memWrite,
    output reg memRead,
    output reg halt,
    output reg [1:0] ALUop
);
    always @(*) begin
        RegWrite = 1'b0;
        MemToReg = 1'b0;
        ALUsrc   = 1'b0;
        branch   = 1'b0;
        jump     = 1'b0;
        memWrite = 1'b0;
        memRead  = 1'b0;
        ALUop    = 2'b00;
        halt     = 1'b0;

        case (opcode)
            7'b0110011: begin // R-type
                RegWrite = 1'b1;
                ALUsrc   = 1'b0;
                ALUop    = 2'b10;
            end
            7'b0010011: begin // I-type
                RegWrite = 1'b1;
                ALUsrc   = 1'b1;
                ALUop    = 2'b10;
            end
            7'b0000011: begin // Load (LW)
                RegWrite = 1'b1;
                MemToReg = 1'b1;
                ALUsrc   = 1'b1;
                memRead  = 1'b1;
                ALUop    = 2'b00;
            end
            7'b0100011: begin // Store (SW)
                ALUsrc   = 1'b1;
                memWrite = 1'b1;
                ALUop    = 2'b00;
            end
            7'b1100011: begin // Branch
                branch   = 1'b1;
                ALUop    = 2'b01;
            end
            7'b1101111: begin // JAL
                RegWrite = 1'b1;
                jump     = 1'b1;
            end
            7'b1111111: begin // Custom Halt
                halt     = 1'b1;
            end
        endcase
    end
endmodule

// ============================================================================
// 11. ALU Control Unit
// ============================================================================
module alu_control_datapath(
    input [1:0] ALUop,
    input [2:0] func3,
    input func7,
    input [6:0] opcode,
    output reg [3:0] ALUoperation
);
    wire is_rtype = (opcode == 7'b0110011);

    always @(*) begin
        case (ALUop)
            2'b00: ALUoperation = 4'b0000; // ADD
            2'b01: ALUoperation = 4'b0001; // SUB
            2'b10: begin
                case (func3)
                    3'b000: ALUoperation = (func7 && is_rtype) ? 4'b0001 : 4'b0000; // SUB : ADD
                    3'b001: ALUoperation = 4'b0010;                               // SLL
                    3'b010: ALUoperation = 4'b0011;                               // SLT
                    3'b011: ALUoperation = 4'b0100;                               // SLTU
                    3'b100: ALUoperation = 4'b0101;                               // XOR
                    3'b101: ALUoperation = (func7) ? 4'b0111 : 4'b0110;           // SRA : SRL
                    3'b110: ALUoperation = 4'b1000;                               // OR
                    3'b111: ALUoperation = 4'b1001;                               // AND
                    default: ALUoperation = 4'b1111;
                endcase
            end
            default: ALUoperation = 4'b1111;
        endcase
    end
endmodule

// ============================================================================
// 12. Top-Level RISC-V Processor Datapath
// ============================================================================
module risc_v_datapath(
    input clk,
    input reset
);
    wire RegWrite, ALUsrc, memRead, memWrite, MemToReg, branch, jump, func7, halt;
    wire [3:0] ALUoperation;
    wire [6:0] opcode;
    wire [2:0] func;
    wire [1:0] ALUop;

    control_unit_datapath CUD(
        .opcode(opcode),
        .RegWrite(RegWrite),
        .halt(halt),
        .MemToReg(MemToReg),
        .ALUsrc(ALUsrc),
        .branch(branch),
        .jump(jump),
        .memWrite(memWrite),
        .memRead(memRead),
        .ALUop(ALUop)
    );

    alu_control_datapath ACD(
        .ALUop(ALUop),
        .func3(func),
        .func7(func7),
        .opcode(opcode),
        .ALUoperation(ALUoperation)
    );

    SCDP_without_control_unit SCDP(
        .clk(clk),
        .reset(reset),
        .halt(halt),
        .RegWrite(RegWrite),
        .ALUsrc(ALUsrc),
        .memRead(memRead),
        .memWrite(memWrite),
        .MemToReg(MemToReg),
        .branch(branch),
        .jump(jump),
        .func7(func7),
        .ALUoperation(ALUoperation),
        .opcode(opcode),
        .func(func)
    );
endmodule
