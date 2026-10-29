-- cpu_pkg.vhd
-- Shared types and encodings for the 16-bit multi-cycle CPU.
--
-- Instruction formats (16 bits):
--   R : [15:12] op=0000 | [11:9] rd | [8:6] rs1 | [5:3] rs2 | [2:0] funct
--   I : [15:12] op      | [11:9] rd | [8:6] rs1 | [5:0] simm6
--   U : [15:12] op      | [11:9] rd | [8]  0    | [7:0] imm8
--   J : [15:12] op      | [11:9] rd | [8:0] simm9
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package cpu_pkg is

  constant XLEN : natural := 16;
  subtype word_t is std_logic_vector(XLEN - 1 downto 0);
  subtype reg_addr_t is std_logic_vector(2 downto 0);
  subtype opcode_t is std_logic_vector(3 downto 0);
  subtype alu_op_t is std_logic_vector(3 downto 0);

  -- Major opcodes
  constant OP_ALU  : opcode_t := "0000";
  constant OP_ADDI : opcode_t := "0001";
  constant OP_LUI  : opcode_t := "0010";
  constant OP_LLI  : opcode_t := "0011";
  constant OP_LW   : opcode_t := "0100";
  constant OP_SW   : opcode_t := "0101";
  constant OP_BEQ  : opcode_t := "0110";
  constant OP_BNE  : opcode_t := "0111";
  constant OP_JAL  : opcode_t := "1000";
  constant OP_JR   : opcode_t := "1001";
  constant OP_NOP  : opcode_t := "1110";
  constant OP_HALT : opcode_t := "1111";

  -- ALU operations (funct field of R-type maps onto the low 3 bits)
  constant ALU_ADD  : alu_op_t := "0000";
  constant ALU_SUB  : alu_op_t := "0001";
  constant ALU_AND  : alu_op_t := "0010";
  constant ALU_OR   : alu_op_t := "0011";
  constant ALU_XOR  : alu_op_t := "0100";
  constant ALU_SLT  : alu_op_t := "0101";
  constant ALU_SLL  : alu_op_t := "0110";
  constant ALU_SRL  : alu_op_t := "0111";
  constant ALU_PASB : alu_op_t := "1000";
  constant ALU_LLI  : alu_op_t := "1001";  -- (a and 0xFF00) or (b and 0x00FF)

  -- Datapath mux selects
  subtype sel2_t is std_logic_vector(1 downto 0);
  constant PC_SRC_ALU    : sel2_t := "00";  -- combinational ALU result
  constant PC_SRC_ALUOUT : sel2_t := "01";  -- registered ALU result
  constant PC_SRC_A      : sel2_t := "10";  -- register A (JR)

  constant ALUB_B     : sel2_t := "00";
  constant ALUB_ONE   : sel2_t := "01";
  constant ALUB_IMM   : sel2_t := "10";

  constant IMM_S6  : sel2_t := "00";
  constant IMM_S9  : sel2_t := "01";
  constant IMM_U8H : sel2_t := "10";  -- imm8 << 8
  constant IMM_U8L : sel2_t := "11";  -- zero-extended imm8

  constant WB_ALUOUT : sel2_t := "00";
  constant WB_MDR    : sel2_t := "01";
  constant WB_PC     : sel2_t := "10";

  -- Control word driven by the control unit into the datapath
  type ctrl_t is record
    pc_we     : std_logic;
    pc_src    : sel2_t;
    ir_we     : std_logic;
    iord      : std_logic;              -- 0: PC addresses memory, 1: ALUOut
    mem_req   : std_logic;
    mem_we    : std_logic;
    mdr_we    : std_logic;
    alu_src_a : std_logic;              -- 0: PC, 1: A
    alu_src_b : sel2_t;
    imm_sel   : sel2_t;
    alu_op    : alu_op_t;
    aluout_we : std_logic;
    reg_we    : std_logic;
    wb_sel    : sel2_t;
    ra_sel    : std_logic;              -- 0: ir[8:6], 1: ir[11:9]
    rb_sel    : std_logic;              -- 0: ir[5:3], 1: ir[11:9]
  end record;

  constant CTRL_IDLE : ctrl_t := (
    pc_we => '0', pc_src => PC_SRC_ALU, ir_we => '0', iord => '0',
    mem_req => '0', mem_we => '0', mdr_we => '0', alu_src_a => '0',
    alu_src_b => ALUB_B, imm_sel => IMM_S6, alu_op => ALU_ADD,
    aluout_we => '0', reg_we => '0', wb_sel => WB_ALUOUT,
    ra_sel => '0', rb_sel => '0');

  function funct_to_alu(funct : std_logic_vector(2 downto 0)) return alu_op_t;

end package cpu_pkg;

package body cpu_pkg is

  function funct_to_alu(funct : std_logic_vector(2 downto 0)) return alu_op_t is
  begin
    return '0' & funct;
  end function;

end package body cpu_pkg;
