-- sync_sram.vhd
-- Synchronous single-cycle-latency RAM (read-first) with a second read-only
-- port. Written so that Vivado infers a dual-port block RAM. Contents can be
-- pre-loaded from a text file containing one hexadecimal word per line.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity sync_sram is
  generic (
    ADDR_WIDTH : positive := 12;
    DATA_WIDTH : positive := 16;
    INIT_FILE  : string   := ""
  );
  port (
    clk    : in  std_logic;
    -- port A: read/write
    cs     : in  std_logic;
    we     : in  std_logic;
    addr   : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
    din    : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    dout   : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    -- port B: read-only (debug / DMA style)
    addr_b : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
    dout_b : out std_logic_vector(DATA_WIDTH - 1 downto 0)
  );
end entity sync_sram;

architecture rtl of sync_sram is
  type mem_t is array (0 to 2**ADDR_WIDTH - 1) of std_logic_vector(DATA_WIDTH - 1 downto 0);

  impure function load_mem(fname : string) return mem_t is
    file f       : text;
    variable l   : line;
    variable w   : std_logic_vector(DATA_WIDTH - 1 downto 0);
    variable m   : mem_t := (others => (others => '0'));
    variable i   : natural := 0;
    variable st  : file_open_status;
  begin
    if fname = "" then
      return m;
    end if;
    file_open(st, f, fname, read_mode);
    assert st = open_ok
      report "sync_sram: cannot open init file " & fname severity failure;
    while not endfile(f) and i < 2**ADDR_WIDTH loop
      readline(f, l);
      if l'length > 0 then
        hread(l, w);
        m(i) := w;
        i := i + 1;
      end if;
    end loop;
    file_close(f);
    return m;
  end function;

  signal mem : mem_t := load_mem(INIT_FILE);
begin

  process (clk)
  begin
    if rising_edge(clk) then
      if cs = '1' then
        if we = '1' then
          mem(to_integer(unsigned(addr))) <= din;
        end if;
        dout <= mem(to_integer(unsigned(addr)));
      end if;
      dout_b <= mem(to_integer(unsigned(addr_b)));
    end if;
  end process;

end architecture rtl;
