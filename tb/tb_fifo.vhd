-- tb_fifo.vhd
-- FIFO against a queue model under random push/pop pressure, including
-- push-on-full, pop-on-empty and simultaneous push/pop.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tb_pkg.all;

entity tb_fifo is
end entity tb_fifo;

architecture sim of tb_fifo is
  constant T  : time := 10 ns;
  constant AW : positive := 3;
  signal clk  : std_logic := '0';
  signal rst  : std_logic := '1';
  signal push, pop, empty, full : std_logic := '0';
  signal din, dout : std_logic_vector(7 downto 0) := (others => '0');
  signal count : std_logic_vector(AW downto 0);
  signal done : boolean := false;
  signal cycles : natural := 0;
  shared variable chk : checker_t;
begin

  clk <= not clk after T / 2 when not done;
  process (clk) begin
    if rising_edge(clk) then cycles <= cycles + 1; end if;
  end process;

  dut : entity work.fifo
    generic map (DATA_WIDTH => 8, ADDR_WIDTH => AW)
    port map (clk => clk, rst => rst, push => push, din => din, pop => pop,
              dout => dout, empty => empty, full => full, count => count);

  stim : process
    type q_t is array (0 to 2**AW - 1) of std_logic_vector(7 downto 0);
    variable q        : q_t;
    variable head, n  : natural := 0;
    variable seed     : unsigned(31 downto 0) := x"FEEDBEEF";
    variable r        : std_logic_vector(7 downto 0);
    variable d        : std_logic_vector(7 downto 0);
    variable did_pop, did_push : boolean;
    variable n_full, n_empty, n_both : natural := 0;
  begin
    wait for 2 * T;
    wait until falling_edge(clk);
    rst <= '0';
    for k in 1 to 5000 loop
      lcg_rand(seed, r);
      lcg_rand(seed, d);
      -- three traffic phases: fill-biased, drain-biased, balanced
      if k < 1500 then
        push <= '1' when unsigned(r(3 downto 0)) < 11 else '0';
        pop  <= '1' when unsigned(r(7 downto 4)) < 5 else '0';
      elsif k < 3000 then
        push <= '1' when unsigned(r(3 downto 0)) < 5 else '0';
        pop  <= '1' when unsigned(r(7 downto 4)) < 11 else '0';
      else
        push <= r(0);
        pop  <= r(1);
      end if;
      din <= d;
      wait for 1 ns;
      -- check outputs before the edge
      chk.check((empty = '1') = (n = 0), "empty flag");
      chk.check((full = '1') = (n = 2**AW), "full flag");
      chk.check(to_integer(unsigned(count)) = n, "count");
      if n > 0 then
        chk.check_eq(dout, q(head), "head data");
      end if;
      if empty = '1' then n_empty := n_empty + 1; end if;
      if full = '1' then n_full := n_full + 1; end if;
      -- model the edge
      did_pop  := pop = '1' and n > 0;
      did_push := push = '1' and (n < 2**AW or did_pop);
      if did_pop and did_push then n_both := n_both + 1; end if;
      if did_push then
        q((head + n) mod 2**AW) := d;
      end if;
      if did_pop then
        head := (head + 1) mod 2**AW;
      end if;
      if did_push and not did_pop then n := n + 1;
      elsif did_pop and not did_push then n := n - 1;
      end if;
      wait until falling_edge(clk);
    end loop;
    chk.check(n_full > 50 and n_empty > 50 and n_both > 50,
              "corner conditions exercised: full=" & integer'image(n_full) &
              " empty=" & integer'image(n_empty) & " both=" & integer'image(n_both));
    chk.summary("tb_fifo", cycles);
    done <= true;
    std.env.finish;
  end process;

end architecture sim;
