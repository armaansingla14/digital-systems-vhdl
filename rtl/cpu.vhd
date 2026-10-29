-- cpu.vhd
-- Top level of the 16-bit multi-cycle CPU: control unit + datapath plus
-- cycle and retired-instruction counters.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu_pkg.all;

entity cpu is
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    -- memory bus (request held until ready)
    mem_req   : out std_logic;
    mem_we    : out std_logic;
    mem_addr  : out word_t;
    mem_wdata : out word_t;
    mem_rdata : in  word_t;
    mem_ready : in  std_logic;
    -- status / debug
    halted    : out std_logic;
    illegal   : out std_logic;
    pc_dbg    : out word_t;
    cycles    : out std_logic_vector(31 downto 0);
    instret   : out std_logic_vector(31 downto 0);
    dbg_reg   : in  reg_addr_t;
    dbg_data  : out word_t
  );
end entity cpu;

architecture rtl of cpu is
  signal ctrl     : ctrl_t;
  signal ir       : word_t;
  signal alu_zero : std_logic;
  signal halted_i : std_logic;
  signal retire   : std_logic;
  signal run      : std_logic;
begin

  u_ctrl : entity work.control_unit
    port map (clk => clk, rst => rst, ir => ir, mem_ready => mem_ready,
              alu_zero => alu_zero, ctrl => ctrl, halted => halted_i,
              retire => retire, illegal => illegal, state_dbg => open);

  u_dp : entity work.datapath
    port map (clk => clk, rst => rst, ctrl => ctrl, ir_out => ir,
              alu_zero => alu_zero, mem_addr => mem_addr,
              mem_wdata => mem_wdata, mem_rdata => mem_rdata,
              pc_out => pc_dbg, dbg_reg => dbg_reg, dbg_data => dbg_data);

  run <= not halted_i;

  u_cycles : entity work.counter
    generic map (WIDTH => 32)
    port map (clk => clk, rst => rst, clr => '0', en => run, up => '1',
              load => '0', load_val => (others => '0'), q => cycles,
              wrap => open);

  -- HALT itself is counted as a retired instruction when it is decoded.
  u_instret : entity work.counter
    generic map (WIDTH => 32)
    port map (clk => clk, rst => rst, clr => '0', en => retire, up => '1',
              load => '0', load_val => (others => '0'), q => instret,
              wrap => open);

  mem_req <= ctrl.mem_req;
  mem_we  <= ctrl.mem_we;
  halted  <= halted_i;

end architecture rtl;
