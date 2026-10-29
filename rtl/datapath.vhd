-- datapath.vhd
-- Multi-cycle datapath: PC, IR, MDR, A/B operand latches, ALUOut, the
-- register file, the ALU and the immediate generator.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu_pkg.all;

entity datapath is
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    ctrl      : in  ctrl_t;
    ir_out    : out word_t;
    alu_zero  : out std_logic;
    -- memory bus
    mem_addr  : out word_t;
    mem_wdata : out word_t;
    mem_rdata : in  word_t;
    -- debug
    pc_out    : out word_t;
    dbg_reg   : in  reg_addr_t;
    dbg_data  : out word_t
  );
end entity datapath;

architecture rtl of datapath is
  signal pc, ir, mdr, a_r, b_r, aluout : word_t := (others => '0');
  signal ra_addr, rb_addr              : reg_addr_t;
  signal ra_data, rb_data, wr_data     : word_t;
  signal alu_a, alu_b, alu_y, imm      : word_t;
begin

  -- Immediate generator
  process (all)
  begin
    case ctrl.imm_sel is
      when IMM_S6  => imm <= std_logic_vector(resize(signed(ir(5 downto 0)), XLEN));
      when IMM_S9  => imm <= std_logic_vector(resize(signed(ir(8 downto 0)), XLEN));
      when IMM_U8H => imm <= ir(7 downto 0) & x"00";
      when others  => imm <= x"00" & ir(7 downto 0);
    end case;
  end process;

  ra_addr <= ir(11 downto 9) when ctrl.ra_sel = '1' else ir(8 downto 6);
  rb_addr <= ir(11 downto 9) when ctrl.rb_sel = '1' else ir(5 downto 3);

  with ctrl.wb_sel select wr_data <=
    mdr    when WB_MDR,
    pc     when WB_PC,
    aluout when others;

  u_rf : entity work.regfile
    port map (
      clk => clk, rst => rst,
      ra_addr => ra_addr, rb_addr => rb_addr,
      ra_data => ra_data, rb_data => rb_data,
      we => ctrl.reg_we, wr_addr => ir(11 downto 9), wr_data => wr_data,
      dbg_addr => dbg_reg, dbg_data => dbg_data);

  alu_a <= a_r when ctrl.alu_src_a = '1' else pc;
  with ctrl.alu_src_b select alu_b <=
    x"0001" when ALUB_ONE,
    imm     when ALUB_IMM,
    b_r     when others;

  u_alu : entity work.alu
    port map (a => alu_a, b => alu_b, op => ctrl.alu_op, y => alu_y,
              zero => alu_zero, negative => open, carry => open,
              overflow => open);

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        pc     <= (others => '0');
        ir     <= x"E000";  -- NOP
        mdr    <= (others => '0');
        a_r    <= (others => '0');
        b_r    <= (others => '0');
        aluout <= (others => '0');
      else
        a_r <= ra_data;
        b_r <= rb_data;
        if ctrl.ir_we = '1' then
          ir <= mem_rdata;
        end if;
        if ctrl.mdr_we = '1' then
          mdr <= mem_rdata;
        end if;
        if ctrl.aluout_we = '1' then
          aluout <= alu_y;
        end if;
        if ctrl.pc_we = '1' then
          case ctrl.pc_src is
            when PC_SRC_ALUOUT => pc <= aluout;
            when PC_SRC_A      => pc <= a_r;
            when others        => pc <= alu_y;
          end case;
        end if;
      end if;
    end if;
  end process;

  mem_addr  <= aluout when ctrl.iord = '1' else pc;
  mem_wdata <= b_r;
  ir_out    <= ir;
  pc_out    <= pc;

end architecture rtl;
