`timescale 1ns/1ps

module tb_risc_v_multiply;

    reg clk;
    reg reset;

    // Device Under Test
    risc_v_datapath dut (
        .clk(clk),
        .reset(reset)
    );

    // 100 MHz Clock (10ns period)
    initial clk = 0;
    always #5 clk = ~clk;

    // ---------------------------------------------------------
    // Multiplication Program (Hand-Assembled RV32I Machine Code)
    // Computes: 6 * 7 = 42 via repeated addition
    // ---------------------------------------------------------
    initial begin
        // Setup Registers
        dut.SCDP.IFCT.IMEM.mem[0] = 32'h00600093; // PC  0: addi x1, x0, 6    (multiplicand = 6)
        dut.SCDP.IFCT.IMEM.mem[1] = 32'h00700113; // PC  4: addi x2, x0, 7    (multiplier = 7)
        dut.SCDP.IFCT.IMEM.mem[2] = 32'h00000193; // PC  8: addi x3, x0, 0    (accumulator = 0)
        dut.SCDP.IFCT.IMEM.mem[3] = 32'h00000213; // PC 12: addi x4, x0, 0    (counter = 0)
        
        // Loop Body
        dut.SCDP.IFCT.IMEM.mem[4] = 32'h00220863; // PC 16: beq  x4, x2, +16  (if counter == 7, jump to PC 32)
        dut.SCDP.IFCT.IMEM.mem[5] = 32'h001181b3; // PC 20: add  x3, x3, x1  (accumulator += 6)
        dut.SCDP.IFCT.IMEM.mem[6] = 32'h00120213; // PC 24: addi x4, x4, 1   (counter++)
        dut.SCDP.IFCT.IMEM.mem[7] = 32'hFF5FF06F; // PC 28: FIXED: jal x0, -12 (jump back to PC 16)
        
        // Exit & Store
        dut.SCDP.IFCT.IMEM.mem[8] = 32'h00302023; // PC 32: sw   x3, 0(x0)   (mem[0] = product)
        dut.SCDP.IFCT.IMEM.mem[9] = 32'h0000007F; // PC 36: halt             (freeze PC)
    end

    // Test Control & Verification
    initial begin
        reset = 1;
        #20;
        reset = 0;

        $display("---------------------------------------------------------");
        $display("Starting RISC-V Multiplication Test (6 * 7)...");
        $display("---------------------------------------------------------");
    end

    // Execution Monitor
    always @(negedge clk) begin
        if (!reset) begin
            // Check for Halt
            if (dut.halt) begin
                $display("\n---------------------------------------------------------");
                $display("Multiplication Completed!");
                $display("---------------------------------------------------------");
                
                check("Multiplicand (x1)", dut.SCDP.RF.registers[1], 32'd6);
                check("Multiplier   (x2)", dut.SCDP.RF.registers[2], 32'd7);
                check("Product Reg  (x3)", dut.SCDP.RF.registers[3], 32'd42);
                check("Memory[0] Store  ", dut.SCDP.DM.memory[0],     32'd42);
                
                $display("---------------------------------------------------------");
                $finish;
            end
        end
    end

    // Safety Timeout
    initial begin
        #1000;
        $display("\n[ERROR] Test Timed Out!");
        $finish;
    end

    // Assertion Task
    task check(input [255:0] name, input [31:0] actual, input [31:0] expected);
        begin
            if (actual === expected)
                $display("PASS: %0s = %0d", name, actual);
            else
                $display("FAIL: %0s = %0d (Expected: %0d)", name, actual, expected);
        end
    endtask

endmodule