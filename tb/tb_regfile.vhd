-- tb_regfile.vhd
-- Register file: r0 hardwired to zero, write/read on all registers, both
-- read ports and the debug port, reset clears state.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu_pkg.all;
use work.tb_pkg.all;

entity tb_regfile is
end entity tb_regfile;

architecture sim of tb_regfile is
  constant T : time := 10 ns;
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal ra_addr, rb_addr, wr_addr, dbg_addr : reg_addr_t := "000";
  signal ra_data, rb_data, dbg_data, wr_data : word_t;
  signal we      : std_logic := '0';
  signal cycles  : natural := 0;
  signal done    : boolean := false;
  shared variable chk : checker_t;
begin

  clk <= not clk after T / 2 when not done;
  process (clk) begin
    if rising_edge(clk) then cycles <= cycles + 1; end if;
  end process;

  dut : entity work.regfile
    port map (clk => clk, rst => rst, ra_addr => ra_addr, rb_addr => rb_addr,
              ra_data => ra_data, rb_data => rb_data, we => we,
              wr_addr => wr_addr, wr_data => wr_data,
              dbg_addr => dbg_addr, dbg_data => dbg_data);

  stim : process
    type model_t is array (0 to 7) of word_t;
    variable model : model_t := (others => (others => '0'));
    variable seed  : unsigned(31 downto 0) := x"00C0FFEE";
    variable rv    : std_logic_vector(15 downto 0);
    variable ri    : std_logic_vector(2 downto 0);
    variable rj    : std_logic_vector(2 downto 0);
  begin
    wait for 2 * T;
    wait until falling_edge(clk);
    rst <= '0';
    -- write a distinct pattern to every register (including r0)
    for i in 0 to 7 loop
      we <= '1';
      wr_addr <= std_logic_vector(to_unsigned(i, 3));
      wr_data <= std_logic_vector(to_unsigned(16#1111# * (i + 1), 16));
      if i /= 0 then
        model(i) := std_logic_vector(to_unsigned(16#1111# * (i + 1), 16));
      end if;
      wait until falling_edge(clk);
    end loop;
    we <= '0';
    for i in 0 to 7 loop
      ra_addr  <= std_logic_vector(to_unsigned(i, 3));
      rb_addr  <= std_logic_vector(to_unsigned(7 - i, 3));
      dbg_addr <= std_logic_vector(to_unsigned(i, 3));
      wait for 1 ns;
      chk.check_eq(ra_data, model(i), "port A r" & integer'image(i));
      chk.check_eq(rb_data, model(7 - i), "port B r" & integer'image(7 - i));
      chk.check_eq(dbg_data, model(i), "debug r" & integer'image(i));
    end loop;
    chk.check_eq(ra_data, model(7), "sanity");
    -- random write/read traffic
    for n in 1 to 500 loop
      wait until falling_edge(clk);
      lcg_rand(seed, ri);
      lcg_rand(seed, rv);
      we      <= '1';
      wr_addr <= ri;
      wr_data <= rv;
      if ri /= "000" then
        model(to_integer(unsigned(ri))) := rv;
      end if;
      wait until falling_edge(clk);
      we <= '0';
      lcg_rand(seed, ri);
      lcg_rand(seed, rj);
      ra_addr <= ri;
      rb_addr <= rj;
      wait for 1 ns;
      chk.check_eq(ra_data, model(to_integer(unsigned(ri))), "rand A");
      chk.check_eq(rb_data, model(to_integer(unsigned(rj))), "rand B");
    end loop;
    -- reset clears everything
    rst <= '1';
    wait until falling_edge(clk);
    rst <= '0';
    for i in 0 to 7 loop
      dbg_addr <= std_logic_vector(to_unsigned(i, 3));
      wait for 1 ns;
      chk.check_eq(dbg_data, x"0000", "after reset r" & integer'image(i));
    end loop;
    chk.summary("tb_regfile", cycles);
    done <= true;
    std.env.finish;
  end process;

end architecture sim;
