-- baud_gen.vhd
-- Produces a single-cycle tick at 16x the baud rate.
-- DIVISOR = round(f_clk / (16 * baud)); e.g. 100 MHz / (16 * 115200) = 54.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity baud_gen is
  generic (
    DIVISOR : positive := 54
  );
  port (
    clk    : in  std_logic;
    rst    : in  std_logic;
    tick16 : out std_logic
  );
end entity baud_gen;

architecture rtl of baud_gen is
  function cnt_width(n : positive) return positive is
    variable w : positive := 1;
  begin
    while 2**w < n loop
      w := w + 1;
    end loop;
    return w;
  end function;
  constant W : positive := cnt_width(DIVISOR);
  signal wrap : std_logic;
begin

  g_div1 : if DIVISOR = 1 generate
    tick16 <= not rst;
  end generate;

  g_div : if DIVISOR > 1 generate
    signal q : std_logic_vector(W - 1 downto 0);
  begin
    u_cnt : entity work.counter
      generic map (WIDTH => W, MODULUS => DIVISOR)
      port map (clk => clk, rst => rst, clr => '0', en => '1', up => '1',
                load => '0', load_val => (others => '0'), q => q,
                wrap => wrap);
    tick16 <= wrap;
  end generate;

end architecture rtl;
