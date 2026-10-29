-- control_unit.vhd
-- Multi-cycle control FSM. Each instruction passes through FETCH and DECODE
-- and then one to three execution states. Memory accesses hold mem_req high
-- until the memory interface returns mem_ready, so any number of wait
-- states is tolerated.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu_pkg.all;

entity control_unit is
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    ir        : in  word_t;      -- registered instruction
    mem_ready : in  std_logic;
    alu_zero  : in  std_logic;
    ctrl      : out ctrl_t;
    halted    : out std_logic;
    retire    : out std_logic;   -- one pulse per completed instruction
    illegal   : out std_logic;   -- sticky: unknown opcode seen
    state_dbg : out std_logic_vector(3 downto 0)
  );
end entity control_unit;

architecture rtl of control_unit is
  type state_t is (S_FETCH, S_DECODE, S_EXEC_R, S_EXEC_I, S_EXEC_LUI,
                   S_EXEC_LLI, S_ADDR, S_MEM_RD, S_MEM_WR, S_WB_ALU,
                   S_WB_MEM, S_BRANCH, S_JAL, S_JR, S_HALT);
  signal state, next_state : state_t := S_FETCH;
  signal illegal_r         : std_logic := '0';
  signal opcode            : opcode_t;
begin

  opcode <= ir(15 downto 12);

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state     <= S_FETCH;
        illegal_r <= '0';
      else
        state <= next_state;
        if state = S_DECODE then
          case opcode is
            when OP_ALU | OP_ADDI | OP_LUI | OP_LLI | OP_LW | OP_SW |
                 OP_BEQ | OP_BNE | OP_JAL | OP_JR | OP_NOP | OP_HALT => null;
            when others => illegal_r <= '1';
          end case;
        end if;
      end if;
    end if;
  end process;

  process (all)
    variable c : ctrl_t;
  begin
    c          := CTRL_IDLE;
    next_state <= state;
    retire     <= '0';

    -- Register read port selects depend only on the instruction format and
    -- are held stable for the whole instruction.
    case opcode is
      when OP_LLI          => c.ra_sel := '1';
      when OP_SW | OP_BEQ | OP_BNE => c.rb_sel := '1';
      when others          => null;
    end case;

    case state is
      when S_FETCH =>
        c.mem_req   := '1';
        c.iord      := '0';
        -- PC + 1 is computed by the ALU while the fetch is outstanding.
        c.alu_src_a := '0';
        c.alu_src_b := ALUB_ONE;
        c.alu_op    := ALU_ADD;
        if mem_ready = '1' then
          c.ir_we  := '1';
          c.pc_we  := '1';
          c.pc_src := PC_SRC_ALU;
          next_state <= S_DECODE;
        end if;

      when S_DECODE =>
        -- Speculatively compute a PC-relative target into ALUOut.
        c.alu_src_a := '0';
        c.alu_src_b := ALUB_IMM;
        c.alu_op    := ALU_ADD;
        c.aluout_we := '1';
        if opcode = OP_JAL then
          c.imm_sel := IMM_S9;
        else
          c.imm_sel := IMM_S6;
        end if;
        case opcode is
          when OP_ALU          => next_state <= S_EXEC_R;
          when OP_ADDI         => next_state <= S_EXEC_I;
          when OP_LUI          => next_state <= S_EXEC_LUI;
          when OP_LLI          => next_state <= S_EXEC_LLI;
          when OP_LW | OP_SW   => next_state <= S_ADDR;
          when OP_BEQ | OP_BNE => next_state <= S_BRANCH;
          when OP_JAL          => next_state <= S_JAL;
          when OP_JR           => next_state <= S_JR;
          when OP_HALT         =>
            retire     <= '1';
            next_state <= S_HALT;
          when others          =>   -- NOP and illegal opcodes
            retire     <= '1';
            next_state <= S_FETCH;
        end case;

      when S_EXEC_R =>
        c.alu_src_a := '1';
        c.alu_src_b := ALUB_B;
        c.alu_op    := funct_to_alu(ir(2 downto 0));
        c.aluout_we := '1';
        next_state  <= S_WB_ALU;

      when S_EXEC_I =>
        c.alu_src_a := '1';
        c.alu_src_b := ALUB_IMM;
        c.imm_sel   := IMM_S6;
        c.alu_op    := ALU_ADD;
        c.aluout_we := '1';
        next_state  <= S_WB_ALU;

      when S_EXEC_LUI =>
        c.alu_src_b := ALUB_IMM;
        c.imm_sel   := IMM_U8H;
        c.alu_op    := ALU_PASB;
        c.aluout_we := '1';
        next_state  <= S_WB_ALU;

      when S_EXEC_LLI =>
        c.alu_src_a := '1';
        c.alu_src_b := ALUB_IMM;
        c.imm_sel   := IMM_U8L;
        c.alu_op    := ALU_LLI;
        c.aluout_we := '1';
        next_state  <= S_WB_ALU;

      when S_ADDR =>
        c.alu_src_a := '1';
        c.alu_src_b := ALUB_IMM;
        c.imm_sel   := IMM_S6;
        c.alu_op    := ALU_ADD;
        c.aluout_we := '1';
        if opcode = OP_LW then
          next_state <= S_MEM_RD;
        else
          next_state <= S_MEM_WR;
        end if;

      when S_MEM_RD =>
        c.mem_req := '1';
        c.iord    := '1';
        if mem_ready = '1' then
          c.mdr_we   := '1';
          next_state <= S_WB_MEM;
        end if;

      when S_MEM_WR =>
        c.mem_req := '1';
        c.mem_we  := '1';
        c.iord    := '1';
        if mem_ready = '1' then
          retire     <= '1';
          next_state <= S_FETCH;
        end if;

      when S_WB_ALU =>
        c.reg_we   := '1';
        c.wb_sel   := WB_ALUOUT;
        retire     <= '1';
        next_state <= S_FETCH;

      when S_WB_MEM =>
        c.reg_we   := '1';
        c.wb_sel   := WB_MDR;
        retire     <= '1';
        next_state <= S_FETCH;

      when S_BRANCH =>
        c.alu_src_a := '1';
        c.alu_src_b := ALUB_B;
        c.alu_op    := ALU_SUB;
        if (opcode = OP_BEQ and alu_zero = '1') or
           (opcode = OP_BNE and alu_zero = '0') then
          c.pc_we  := '1';
          c.pc_src := PC_SRC_ALUOUT;
        end if;
        retire     <= '1';
        next_state <= S_FETCH;

      when S_JAL =>
        c.reg_we   := '1';
        c.wb_sel   := WB_PC;
        c.pc_we    := '1';
        c.pc_src   := PC_SRC_ALUOUT;
        retire     <= '1';
        next_state <= S_FETCH;

      when S_JR =>
        c.pc_we    := '1';
        c.pc_src   := PC_SRC_A;
        retire     <= '1';
        next_state <= S_FETCH;

      when S_HALT =>
        next_state <= S_HALT;
    end case;

    ctrl <= c;
  end process;

  halted    <= '1' when state = S_HALT else '0';
  illegal   <= illegal_r;
  state_dbg <= std_logic_vector(to_unsigned(state_t'pos(state), 4));

end architecture rtl;
