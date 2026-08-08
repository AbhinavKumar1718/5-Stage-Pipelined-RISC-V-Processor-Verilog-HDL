`timescale 1ns / 1ps

module tb_risc_v_pipelining();

    // System Signals
    reg clk;
    reg reset;

    // Instantiate Top-Level RISC-V Processor
    risc_v_pipelining uut (
        .clk(clk),
        .reset(reset)
    );
  initial begin
   
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_risc_v_pipelining); 
end

    // ---------------------------------------------------------
    // Clock Generation (100MHz -> 10ns period)
    // ---------------------------------------------------------
    always #5 clk = ~clk;

    // ---------------------------------------------------------
    // Main Test Stimulus
    // ---------------------------------------------------------
    initial begin
        // Initialize Signals
        clk = 0;
        reset = 1;

        // Load Test Instructions into Instruction Memory
        // Program Flow:
        // 1. ADDI x1, x0, 10    (x1 = 10)
        // 2. ADDI x2, x0, 20    (x2 = 20)
        // 3. ADD  x3, x1, x2    (x3 = 30)
        // 4. SW   x3, 0(x0)     (DataMem[0] = 30)
        // 5. LW   x4, 0(x0)     (x4 = 30)
        // 6. BEQ  x3, x4, 8     (Branch to PC+8 if x3 == x4)
        // 7. ADDI x5, x0, 99    (Skipped due to branch)
        // 8. ADDI x5, x0, 42    (Target of branch -> x5 = 42)
        // 9. HALT               (Custom Halt Instruction)

        uut.IM_inst.mem[0] = 32'h00a00093; // ADDI x1, x0, 10
        uut.IM_inst.mem[1] = 32'h01400113; // ADDI x2, x0, 20
        uut.IM_inst.mem[2] = 32'h002081b3; // ADD  x3, x1, x2
        uut.IM_inst.mem[3] = 32'h00302023; // SW   x3, 0(x0)
        uut.IM_inst.mem[4] = 32'h00002203; // LW   x4, 0(x0)
        uut.IM_inst.mem[5] = 32'h00418463; // BEQ  x3, x4, +8
        uut.IM_inst.mem[6] = 32'h06300293; // ADDI x5, x0, 99 (Skipped)
        uut.IM_inst.mem[7] = 32'h02a00293; // ADDI x5, x0, 42
        uut.IM_inst.mem[8] = 32'h0000007f; // HALT

        // Hold reset for 2 clock cycles
        #20;
        reset = 0;

        // Monitor Pipeline Execution Cycle-by-Cycle
        $display("\n=======================================================");
        $display("          RISC-V PIPELINE EXECUTION SIMULATION          ");
        $display("=======================================================");
        $display(" Time |  PC  | Reg x1 | Reg x2 | Reg x3 | Reg x4 | Reg x5 ");
        $display("-------------------------------------------------------");

        // Run simulation until HALT signal is triggered or timeout occurs
        fork
            begin
                wait (uut.ex_halt == 1'b1);
                #20; // Allow remaining instructions in pipeline to drain
                $display("-------------------------------------------------------");
                $display("[SUCCESS] HALT Signal Asserted at time %0t ps", $time);
                $display("=======================================================");
                
                // Final Register Checks
                $display("\nFinal Register State Verification:");
                $display("  x1 (Expected: 10) = %0d", uut.RF_inst.registers[1]);
                $display("  x2 (Expected: 20) = %0d", uut.RF_inst.registers[2]);
                $display("  x3 (Expected: 30) = %0d", uut.RF_inst.registers[3]);
                $display("  x4 (Expected: 30) = %0d", uut.RF_inst.registers[4]);
                $display("  x5 (Expected: 42) = %0d", uut.RF_inst.registers[5]);
                $display("  DataMem[0]        = %0d", uut.DM_inst.memory[0]);
                $finish;
            end
            begin
                #500; // Timeout threshold
                $display("\n[ERROR] Simulation Timed Out!");
                $finish;
            end
        join
    end

    // Print register state on every rising edge of clock
    always @(posedge clk) begin
        if (!reset) begin
            $display("%5t  |  %0d  |   %0d   |   %0d   |   %0d   |   %0d   |   %0d",
                     $time, uut.pc,
                     uut.RF_inst.registers[1],
                     uut.RF_inst.registers[2],
                     uut.RF_inst.registers[3],
                     uut.RF_inst.registers[4],
                     uut.RF_inst.registers[5]);
        end
    end

    // VCD Waveform Dump for GTKWave / EDA Playground
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_risc_v_pipelining);
    end

endmodule
