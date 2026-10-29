-- fifo.vhd
-- Synchronous first-word-fall-through FIFO with power-of-two depth.
-- Simultaneous push and pop is supported when the FIFO is neither empty
-- (for pop) nor full (for push without pop).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fifo is
  generic (
    DATA_WIDTH : positive := 8;
    ADDR_WIDTH : positive := 3
  );
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;
    push  : in  std_logic;
    din   : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    pop   : in  std_logic;
    dout  : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    empty : out std_logic;
    full  : out std_logic;
    count : out std_logic_vector(ADDR_WIDTH downto 0)
  );
end entity fifo;

architecture rtl of fifo is
  constant DEPTH : positive := 2**ADDR_WIDTH;
  type mem_t is array (0 to DEPTH - 1) of std_logic_vector(DATA_WIDTH - 1 downto 0);
  signal mem    : mem_t := (others => (others => '0'));
  signal wr_ptr : unsigned(ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal rd_ptr : unsigned(ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal cnt    : unsigned(ADDR_WIDTH downto 0)     := (others => '0');
  signal do_push, do_pop : std_logic;
begin

  do_pop  <= pop  when cnt /= 0 else '0';
  do_push <= push when (cnt /= DEPTH or do_pop = '1') else '0';

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        wr_ptr <= (others => '0');
        rd_ptr <= (others => '0');
        cnt    <= (others => '0');
      else
        if do_push = '1' then
          mem(to_integer(wr_ptr)) <= din;
          wr_ptr <= wr_ptr + 1;
        end if;
        if do_pop = '1' then
          rd_ptr <= rd_ptr + 1;
        end if;
        if do_push = '1' and do_pop = '0' then
          cnt <= cnt + 1;
        elsif do_push = '0' and do_pop = '1' then
          cnt <= cnt - 1;
        end if;
      end if;
    end if;
  end process;

  dout  <= mem(to_integer(rd_ptr));
  empty <= '1' when cnt = 0 else '0';
  full  <= '1' when cnt = DEPTH else '0';
  count <= std_logic_vector(cnt);

end architecture rtl;
