// Copyright 2015 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the “License”); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

////////////////////////////////////////////////////////////////////////////////
// Engineer:       Andreas Traber - atraber@iis.ee.ethz.ch                    //
//                                                                            //
// Additional contributions by:                                               //
//                                                                            //
// Design Name:    RISC-V Tracer                                              //
// Project Name:   RI5CY                                                      //
// Language:       SystemVerilog                                              //
//                                                                            //
// Description:    Traces the executed instructions                           //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////


`include "riscv_defines.sv"

module riscv_tracer
(
  // Clock and Reset
  input  logic        clk,
  input  logic        rst_n,

  input  logic [4:0]  core_id,

  input  logic [31:0] pc,
  input  logic [31:0] instr,
  input  logic        compressed,
  input  logic        id_valid,
  input  logic        is_decoding,
  input  logic        pipe_flush,

  input  logic [31:0] rs1_value,
  input  logic [31:0] rs2_value,
  input  logic [31:0] rs3_value,

  input  logic [31:0] imm_u_type,
  input  logic [31:0] imm_uj_type,
  input  logic [31:0] imm_i_type,
  input  logic [31:0] imm_iz_type,
  input  logic [31:0] imm_z_type,
  input  logic [31:0] imm_s_type,
  input  logic [31:0] imm_sb_type

);

  integer      f;
  string       fn;
  integer      cycles;
  logic  [4:0] rd, rs1, rs2, rs3;
  logic [31:0] imm;

  typedef struct {
    time         simtime;
    integer      cycles;
    logic [31:0] pc;
    logic [31:0] instr;
    string       mnemonic;
  } instr_trace_t;

  instr_trace_t queue[$];

  // cycle counter
  always_ff @(posedge clk, negedge rst_n)
  begin
    if (rst_n == 1'b0)
      cycles = 0;
    else
      cycles = cycles + 1;
  end

  // open/close output file for writing
  initial
  begin
    #1 // delay needed for valid core_id
    $sformat(fn, "trace_core_%h.log", core_id);
    $display("[TRACER] Output filename is: %s", fn);
    f = $fopen(fn, "w");
    $fwrite(f, "%20s\t%6s\t%10s\t%10s\t \t%s\n", "Time", "Cycles", "PC", "Instr", "Mnemonic");
  end

  final
  begin
    $fclose(f);
  end

  // actual tracing
  always @(negedge clk)
  begin
    instr_trace_t trace;

    if (queue.size() > 0) begin
      trace = queue.pop_front();

      $fwrite(f, "%t\t%6d\t0x%h\t0x%h\t%s\n", trace.simtime,
                                              trace.cycles,
                                              trace.pc,
                                              trace.instr,
                                              trace.mnemonic);
    end
  end

  // log execution
  always @(posedge clk)
  begin
    instr_trace_t trace;

    // special case for WFI because we don't wait for unstalling there
    if ((id_valid && is_decoding) || pipe_flush)
    begin
      trace.simtime  = $time;
      trace.cycles   = cycles;
      trace.pc       = pc;
      trace.instr    = instr;
      trace.mnemonic = "sdf";

      // get register values
      rd         = instr[`REG_D];
      rs1        = instr[`REG_S1];
      rs2        = instr[`REG_S2];
      rs3        = instr[`REG_S3];

      imm = 0;

      // use casex instead of case inside due to ModelSim bug
      casex (instr)
        // Aliases
        32'h00_00_00_13:   trace.mnemonic = printMnemonic("NOP");
        // Regular opcodes
        `INSTR_LUI:        trace.mnemonic = printUInstr("LUI");
        `INSTR_AUIPC:      trace.mnemonic = printUInstr("AUIPC");
        `INSTR_JAL:        trace.mnemonic = printUJInstr("JAL");
        `INSTR_JALR:       trace.mnemonic = printIInstr("JALR");
        // BRANCH
        `INSTR_BEQ:        trace.mnemonic = printSBInstr("BEQ");
        `INSTR_BNE:        trace.mnemonic = printSBInstr("BNE");
        `INSTR_BLT:        trace.mnemonic = printSBInstr("BLT");
        `INSTR_BGE:        trace.mnemonic = printSBInstr("BGE");
        `INSTR_BLTU:       trace.mnemonic = printSBInstr("BLTU");
        `INSTR_BGEU:       trace.mnemonic = printSBInstr("BGEU");
        // OPIMM
        `INSTR_ADDI:       trace.mnemonic = printIInstr("ADDI");
        `INSTR_SLTI:       trace.mnemonic = printIInstr("SLTI");
        `INSTR_SLTIU:      trace.mnemonic = printIInstr("SLTIU");
        `INSTR_XORI:       trace.mnemonic = printIInstr("XORI");
        `INSTR_ORI:        trace.mnemonic = printIInstr("ORI");
        `INSTR_ANDI:       trace.mnemonic = printIInstr("ANDI");
        `INSTR_SLLI:       trace.mnemonic = printIInstr("SLLI");
        `INSTR_SRLI:       trace.mnemonic = printIInstr("SRLI");
        `INSTR_SRAI:       trace.mnemonic = printIInstr("SRAI");
        // OP
        `INSTR_ADD:        trace.mnemonic = printRInstr("ADD");
        `INSTR_SUB:        trace.mnemonic = printRInstr("SUB");
        `INSTR_SLL:        trace.mnemonic = printRInstr("SLL");
        `INSTR_SLT:        trace.mnemonic = printRInstr("SLT");
        `INSTR_SLTU:       trace.mnemonic = printRInstr("SLTU");
        `INSTR_XOR:        trace.mnemonic = printRInstr("XOR");
        `INSTR_SRL:        trace.mnemonic = printRInstr("SRL");
        `INSTR_SRA:        trace.mnemonic = printRInstr("SRA");
        `INSTR_OR:         trace.mnemonic = printRInstr("OR");
        `INSTR_AND:        trace.mnemonic = printRInstr("AND");
        `INSTR_EXTHS:      trace.mnemonic = printRInstr("EXTHS");
        `INSTR_EXTHZ:      trace.mnemonic = printRInstr("EXTHZ");
        `INSTR_EXTBS:      trace.mnemonic = printRInstr("EXTBS");
        `INSTR_EXTBZ:      trace.mnemonic = printRInstr("EXTBZ");
        // FENCE
        `INSTR_FENCE:      trace.mnemonic = printMnemonic("FENCE");
        `INSTR_FENCEI:     trace.mnemonic = printMnemonic("FENCEI");
        // SYSTEM (CSR manipulation)
        `INSTR_CSRRW:      trace.mnemonic = printCSRInstr("CSRRW");
        `INSTR_CSRRS:      trace.mnemonic = printCSRInstr("CSRRS");
        `INSTR_CSRRC:      trace.mnemonic = printCSRInstr("CSRRC");
        `INSTR_CSRRWI:     trace.mnemonic = printCSRInstr("CSRRWI");
        `INSTR_CSRRSI:     trace.mnemonic = printCSRInstr("CSRRSI");
        `INSTR_CSRRCI:     trace.mnemonic = printCSRInstr("CSRRCI");
        // SYSTEM (others)
        `INSTR_ECALL:      trace.mnemonic = printMnemonic("ECALL");
        `INSTR_EBREAK:     trace.mnemonic = printMnemonic("EBREAK");
        `INSTR_ERET:       trace.mnemonic = printMnemonic("ERET");
        `INSTR_WFI:        trace.mnemonic = printMnemonic("WFI");
        // PULP MULTIPLIER
        `INSTR_PMUL:       trace.mnemonic = printRInstr("P.MUL");
        `INSTR_PMAC:       trace.mnemonic = printRInstr("P.MAC");
        // opcodes with custom decoding
        {25'b?, `OPCODE_LOAD}:       trace.mnemonic = printLoadInstr();
        {25'b?, `OPCODE_LOAD_POST}:  trace.mnemonic = printLoadInstr();
        {25'b?, `OPCODE_STORE}:      trace.mnemonic = printStoreInstr();
        {25'b?, `OPCODE_STORE_POST}: trace.mnemonic = printStoreInstr();
        {25'b?, `OPCODE_HWLOOP}:     trace.mnemonic = printHwloopInstr();
        default:           trace.mnemonic = printMnemonic("INVALID");
      endcase // unique case (instr)

      queue.push_back(trace);
    end
  end // always @ (posedge clk)

  function string printMnemonic(input string mnemonic);
    begin
      return mnemonic;
    end
  endfunction // printMnemonic

  function string printUInstr(input string mnemonic);
    begin
      return $sformatf("%7s\tx%0d, 0x%h (imm)", mnemonic, rd, imm_u_type);
    end
  endfunction // printUInstr

  function string printRInstr(input string mnemonic);
    begin
      return $sformatf("%7s\tx%0d, x%0d (0x%h), x%0d (0x%h)", mnemonic,
                rd, rs1, rs1_value, rs2, rs2_value);
    end
  endfunction // printRInstr

  function string printIInstr(input string mnemonic);
    begin
      return $sformatf("%7s\tx%0d, x%0d (0x%h), 0x%0h (imm)", mnemonic,
                rd, rs1, rs1_value, imm_i_type);
    end
  endfunction // printIInstr

  function string printSBInstr(input string mnemonic);
    begin
      return $sformatf("%7s\tx%0d (0x%h), x%0d (0x%h), 0x%0h (-> 0x%h)", mnemonic,
                rs1, rs1_value, rs2, rs2_value, imm_sb_type, imm_sb_type + pc);
    end
  endfunction // printSBInstr

  function string printUJInstr(input string mnemonic);
    begin
      return $sformatf("%7s\tx%0d, 0x%h (-> 0x%h)", mnemonic, rd, imm_uj_type, imm_uj_type + pc);
    end
  endfunction // printUJInstr

  function string printCSRInstr(input string mnemonic);
    logic [11:0] csr;
    begin
      csr = instr[31:20];

      if (instr[14] == 1'b0) begin
        return $sformatf("%7s\tx%0d, 0x%h (csr), x%0d (0x%h)", mnemonic, rd, csr,
          rs1, rs1_value);
      end else begin
        return $sformatf("%7s\tx%0d, 0x%h (csr), 0x%h (imm)", mnemonic, rd, csr, imm_z_type);
      end
    end
  endfunction // printCSRInstr

  function string printLoadInstr();
    string str;
    string mnemonic;
    logic [2:0] size;
    begin
      // detect reg-reg load and find size
      size = instr[14:12];
      if (instr[14:12] == 3'b111)
        size = instr[30:28];
      case (size)
        3'b000: mnemonic = "LB";
        3'b001: mnemonic = "LH";
        3'b010: mnemonic = "LW";
        3'b100: mnemonic = "LBU";
        3'b101: mnemonic = "LHU";
        3'b011,
        3'b110,
        3'b111: begin
          return printMnemonic("INVALID");
        end
      endcase

      // compose mnemonic
      if (instr[14:12] == 3'b111)
        mnemonic = {mnemonic, "RR"};
      if (instr[6:0] == `OPCODE_LOAD_POST)
        mnemonic = {mnemonic, "POST"};

      if (instr[14:12] != 3'b111) begin
        // regular load
        if (instr[6:0] != `OPCODE_LOAD_POST)
          str = $sformatf("%7s\tx%0d, x%0d (0x%h), 0x%0h (imm) (-> 0x%h)",
                    mnemonic, rd, rs1, rs1_value, imm_i_type, imm_i_type+rs1_value);
        else
          str = $sformatf("%7s\tx%0d, x%0d! (0x%h), 0x%0h (imm) (-> 0x%h)",
                    mnemonic, rd, rs1, rs1_value, imm_i_type, rs1_value);
      end else begin
        // reg-reg load
        if (instr[6:0] != `OPCODE_LOAD_POST)
          str = $sformatf("%7s\tx%0d, x%0d (0x%h), x%0d (0x%h) (-> 0x%h)", mnemonic,
                    rd, rs1, rs1_value, rs2, rs2_value, rs1_value+rs2_value);
        else
          str = $sformatf("%7s\tx%0d, x%0d! (0x%h), x%0d (0x%h) (-> 0x%h)", mnemonic,
                    rd, rs1, rs1_value, rs2, rs2_value, rs1_value);
      end

      return str;
    end
  endfunction

  function string printStoreInstr();
    string mnemonic;
    string str;
    begin
      case (instr[13:12])
        2'b00:  mnemonic = "SB";
        2'b01:  mnemonic = "SH";
        2'b10:  mnemonic = "SW";
        2'b11: begin
          return printMnemonic("INVALID");
        end
      endcase

      // compose mnemonic
      if (instr[14])
        mnemonic = {mnemonic, "RR"};
      if (instr[6:0] == `OPCODE_STORE_POST)
        mnemonic = {mnemonic, "POST"};

      if (instr[14] == 1'b0) begin
        // regular store
        if (instr[6:0] != `OPCODE_STORE_POST)
          str = $sformatf("%7s\tx%0d (0x%h), x%0d (0x%h), 0x%0h (imm) (-> 0x%h)",
                    mnemonic, rs1, rs1_value, rs2, rs2_value, imm_s_type, imm_s_type+rs1_value);
        else
          str = $sformatf("%7s\tx%0d! (0x%h), x%0d (0x%h), 0x%0h (imm) (-> 0x%h)",
                    mnemonic, rs1, rs1_value, rs2, rs2_value, imm_s_type, rs1_value);
      end else begin
        // reg-reg store
        if (instr[6:0] != `OPCODE_STORE_POST)
          str = $sformatf("%7s\tx%0d (0x%h), x%0d (0x%h), x%0d (0x%h) (-> 0x%h)", mnemonic,
                    rs1, rs1_value, rs2, rs2_value, rs3, rs3_value, rs1_value+rs3_value);
        else
          str = $sformatf("%7s\tx%0d! (0x%h), x%0d (0x%h), x%0d (0x%h) (-> 0x%h)", mnemonic,
                    rs1, rs1_value, rs2, rs2_value, rs3, rs3_value, rs1_value);
      end

      return str;
    end
  endfunction // printSInstr

  function string printHwloopInstr();
    string str;
    string mnemonic;
    begin
      // set mnemonic
      case (instr[14:12])
        3'b000: mnemonic = "LSTARTI";
        3'b001: mnemonic = "LENDI";
        3'b010: mnemonic = "LCOUNT";
        3'b011: mnemonic = "LCOUNTI";
        3'b100: mnemonic = "LSETUP";
        3'b101: mnemonic = "LSETUPI";
        3'b111: begin
          return printMnemonic("INVALID");
        end
      endcase

      // decode and print instruction
      case (instr[14:12])
        // lp.starti and lp.endi
        3'b000,
        3'b001: str = $sformatf("%7s\tx%0d, 0x%h (-> 0x%h)", mnemonic, rd, imm_iz_type, pc + (imm_iz_type << 1));
        // lp.count
        3'b010: str = $sformatf("%7s\tx%0d, x%0d (0x%h)", mnemonic, rd, rs1, rs1_value);
        // lp.counti
        3'b011: str = $sformatf("%7s\tx%0d, 0x%h", mnemonic, rd, imm_iz_type);
        // lp.setup
        3'b100: str = $sformatf("%7s\tx%0d, x%0d (0x%h), 0x%h (-> 0x%h)", mnemonic,
                           rd, rs1, rs1_value, imm_iz_type, pc + (imm_iz_type << 1));
        // lp.setupi
        3'b101: str = $sformatf("%7s\tx%0d, x%0d (0x%h), 0x%h (-> 0x%h)", mnemonic,
                          rd, rs1, rs1_value, imm_iz_type, pc + (imm_z_type << 1));
      endcase

      return str;
    end
  endfunction

endmodule

