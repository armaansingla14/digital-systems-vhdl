-- counter.vhd
-- Generic synchronous up/down counter with clear, parallel load, enable and
-- optional modulus. 'wrap' pulses for one cycle when the count rolls over
-- (MODULUS-1 -> 0 when counting up, 0 -> MODULUS-1 when counting down).
-- MODULUS = 0 selects the natural 2**WIDTH range.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity counter is
  generic (
    WIDTH   : positive := 16;
    MODULUS : natural  := 0
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    clr      : in  std_logic;
    en       : in  std_logic;
    up       : in  std_logic;
    load     : in  std_logic;
    load_val : in  std_logic_vector(WIDTH - 1 downto 0);
    q        : out std_logic_vector(WIDTH - 1 downto 0);
    wrap     : out std_logic
  );
end entity counter;

architecture rtl of counter is
  function top_value return unsigned is
  begin
    if MODULUS = 0 then
      return to_unsigned(2**WIDTH - 1, WIDTH);
    else
      return to_unsigned(MODULUS - 1, WIDTH);
    end if;
  end function;

  constant TOP : unsigned(WIDTH - 1 downto 0) := top_value;
  signal cnt   : unsigned(WIDTH - 1 downto 0) := (others => '0');
begin

  assert MODULUS = 0 or MODULUS <= 2**WIDTH
    report "counter: MODULUS does not fit in WIDTH bits" severity failure;

  process (clk)
  begin
    if rising_edge(clk) then
      wrap <= '0';
      if rst = '1' or clr = '1' then
        cnt <= (others => '0');
      elsif load = '1' then
        cnt <= unsigned(load_val);
      elsif en = '1' then
        if up = '1' then
          if cnt = TOP then
            cnt  <= (others => '0');
            wrap <= '1';
          else
            cnt <= cnt + 1;
          end if;
        else
          if cnt = 0 then
            cnt  <= TOP;
            wrap <= '1';
          else
            cnt <= cnt - 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  q <= std_logic_vector(cnt);

end architecture rtl;
