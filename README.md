#  5-Stage Pipelined RISC-V Core (RV32I)

![Verilog](https://img.shields.io/badge/Language-Verilog_2001-blue.svg)
![Architecture](https://img.shields.io/badge/Architecture-RISC--V_RV32I-orange.svg)
![Simulation](https://img.shields.io/badge/Simulator-Icarus_Verilog-green.svg)

A modular, hardware-verified 32-bit 5-stage pipelined RISC-V processor designed in Verilog. Features full hazard handling including hardware data forwarding, load-use stall detection, pipeline register flushing, and automatic VCD waveform generation.

---

##  Architecture Highlights

* **Classic 5-Stage Pipeline:** `IF` (Fetch) ➔ `ID` (Decode) ➔ `EX` (Execute) ➔ `MEM` (Memory) ➔ `WB` (Write-Back).
* **Data Forwarding Unit:** Eliminates execution delays by forwarding ALU/Memory results (`EX->EX` and `MEM->EX`) to dependent instructions.
* **Hazard Handling & Stalling:** Automatically detects `LW` dependencies and injects a 1-cycle stall bubble into the pipeline.
* **Control Hazard Resolution:** Evaluates conditional branches in the Execute stage and flushes speculatively fetched instructions on branch taken.
* **Zero Stale Reads:** Features internal write-bypass logic inside the Register File to eliminate same-cycle write/read conflicts.

---

##  Instruction Set Support

| Category | Instructions Supported | Operation |
| :--- | :--- | :--- |
| **R-Type** | `ADD`, `SUB`, `AND`, `OR`, `XOR`, `SLL`, `SRL`, `SRA`, `SLT` | Register-Register Operations |
| **I-Type** | `ADDI`, `LW` | Immediate Arithmetic & Memory Loads |
| **S-Type** | `SW` | Memory Stores |
| **B-Type** | `BEQ`, `BNE`, `BLT`, `BGE` | Conditional Branching |
| **J-Type** | `JAL` | Unconditional Jump & Link |
| **Custom** | `HALT` (`0x0000007f`) | Simulation Termination |

---

