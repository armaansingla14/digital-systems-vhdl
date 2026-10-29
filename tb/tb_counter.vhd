-- tb_counter.vhd
-- Generic counter: modulo-10 up count with wrap pulses, down count with
-- underflow wrap, parallel load, enable gating, clear, and the natural
-- 2**WIDTH range. A cycle-by-cycle software model is compared every clock.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tb_pkg.all;

entity tb_counter is
end entity tb_counter;

architecture sim of tb_counter is
  constant T : time := 10 ns;
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal done : boolean := false;
  signal cycles : natural := 0;

  -- DUT 1: modulus 10 in 4 bits
  signal clr, en, up, load : std_logic := '0';
  signal load_val : std_logic_vector(3 downto 0) := (others => '0');
  signal q10      : std_logic_vector(3 downto 0);
  signal wrap10   : std_logic;
  -- DUT 2: natural range, 3 bits
  signal q8       : std_logic_vector(2 downto 0);
  signal wrap8    : std_logic;
  shared variable chk : checker_t;
begin

  clk <= not clk after T / 2 when not done;
  process (clk) begin
    if rising_edge(clk) then cycles <= cycles + 1; end if;
  end process;

  dut10 : entity work.counter
    generic map (WIDTH => 4, MODULUS => 10)
    port map (clk => clk, rst => rst, clr => clr, en => en, up => up,
              load => load, load_val => load_val, q => q10, wrap => wrap10);

  dut8 : entity work.counter
    generic map (WIDTH => 3, MODULUS => 0)
    port map (clk => clk, rst => rst, clr => clr, en => en, up => up,
              load => load, load_val => load_val(2 downto 0), q => q8,
              wrap => wrap8);

  stim : process
    variable seed : unsigned(31 downto 0) := x"0BADF00D";
    variable r    : std_logic_vector(7 downto 0);
    variable m10, m8 : natural := 0;
    variable w10, w8 : std_logic := '0';
    variable n_wrap  : natural := 0;
  begin
    wait for 2 * T;
    wait until falling_edge(clk);
    rst <= '0';
    for n in 1 to 4000 loop
      lcg_rand(seed, r);
      -- bias: mostly enabled counting, occasional load/clear
      en   <= '1' when unsigned(r(7 downto 5)) /= 0 else '0';
      up   <= '1' when n < 1500 or (n >= 3000 and r(4) = '1') else '0';
      load <= '1' when r(3 downto 0) = "0000" else '0';
      clr  <= '1' when r(3 downto 0) = "1111" and r(4) = '1' else '0';
      load_val <= std_logic_vector(unsigned(r(7 downto 4)) mod 10);
      wait until rising_edge(clk);
      -- model update mirrors the RTL priority: clr > load > en
      w10 := '0'; w8 := '0';
      if clr = '1' then
        m10 := 0; m8 := 0;
      elsif load = '1' then
        m10 := to_integer(unsigned(load_val));
        m8  := to_integer(unsigned(load_val(2 downto 0)));
      elsif en = '1' then
        if up = '1' then
          if m10 = 9 then m10 := 0; w10 := '1'; else m10 := m10 + 1; end if;
          if m8 = 7 then m8 := 0; w8 := '1'; else m8 := m8 + 1; end if;
        else
          if m10 = 0 then m10 := 9; w10 := '1'; else m10 := m10 - 1; end if;
          if m8 = 0 then m8 := 7; w8 := '1'; else m8 := m8 - 1; end if;
        end if;
      end if;
      wait until falling_edge(clk);
      chk.check(to_integer(unsigned(q10)) = m10,
                "mod10 q=" & integer'image(to_integer(unsigned(q10))) &
                " exp=" & integer'image(m10));
      chk.check(wrap10 = w10, "mod10 wrap");
      chk.check(to_integer(unsigned(q8)) = m8, "mod8 q");
      chk.check(wrap8 = w8, "mod8 wrap");
      if w10 = '1' then n_wrap := n_wrap + 1; end if;
    end loop;
    chk.check(n_wrap > 100, "wrap events exercised");
    chk.summary("tb_counter", cycles);
    done <= true;
    std.env.finish;
  end process;

end architecture sim;
