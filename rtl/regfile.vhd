-- regfile.vhd
-- 8 x 16-bit register file: two asynchronous read ports, one synchronous
-- write port and a debug read port. Register r0 always reads as zero.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu_pkg.all;

entity regfile is
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    ra_addr  : in  reg_addr_t;
    rb_addr  : in  reg_addr_t;
    ra_data  : out word_t;
    rb_data  : out word_t;
    we       : in  std_logic;
    wr_addr  : in  reg_addr_t;
    wr_data  : in  word_t;
    dbg_addr : in  reg_addr_t;
    dbg_data : out word_t
  );
end entity regfile;

architecture rtl of regfile is
  type reg_array_t is array (0 to 7) of word_t;
  signal regs : reg_array_t := (others => (others => '0'));
begin

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        regs <= (others => (others => '0'));
      elsif we = '1' and wr_addr /= "000" then
        regs(to_integer(unsigned(wr_addr))) <= wr_data;
      end if;
    end if;
  end process;

  ra_data  <= regs(to_integer(unsigned(ra_addr)));
  rb_data  <= regs(to_integer(unsigned(rb_addr)));
  dbg_data <= regs(to_integer(unsigned(dbg_addr)));

end architecture rtl;
