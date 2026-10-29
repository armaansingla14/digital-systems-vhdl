-- tb_sram_ctrl.vhd
-- SRAM controller + synchronous SRAM against a shadow memory with random
-- reads/writes. Checks data and the request-to-ready latency
-- (WAIT_STATES + 1 cycles), and that the SRAM is strobed exactly once per
-- request.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tb_pkg.all;

entity tb_sram_ctrl is
  generic (WAIT_STATES : natural := 0; N_OPS : natural := 3000);
end entity tb_sram_ctrl;

architecture sim of tb_sram_ctrl is
  constant T  : time := 10 ns;
  constant AW : positive := 8;
  signal clk  : std_logic := '0';
  signal rst  : std_logic := '1';
  signal done : boolean := false;
  signal cycles : natural := 0;
  signal req, we, ready : std_logic := '0';
  signal addr  : std_logic_vector(AW - 1 downto 0) := (others => '0');
  signal wdata, rdata : std_logic_vector(15 downto 0) := (others => '0');
  signal s_cs, s_we : std_logic;
  signal s_addr : std_logic_vector(AW - 1 downto 0);
  signal s_din, s_dout : std_logic_vector(15 downto 0);
  signal strobes : natural := 0;
  shared variable chk : checker_t;
begin

  clk <= not clk after T / 2 when not done;
  process (clk) begin
    if rising_edge(clk) then
      cycles <= cycles + 1;
      if s_cs = '1' then strobes <= strobes + 1; end if;
    end if;
  end process;

  u_ctrl : entity work.sram_ctrl
    generic map (ADDR_WIDTH => AW, DATA_WIDTH => 16, WAIT_STATES => WAIT_STATES)
    port map (clk => clk, rst => rst, req => req, we => we, addr => addr,
              wdata => wdata, rdata => rdata, ready => ready,
              sram_cs => s_cs, sram_we => s_we, sram_addr => s_addr,
              sram_din => s_din, sram_dout => s_dout);

  u_ram : entity work.sync_sram
    generic map (ADDR_WIDTH => AW, DATA_WIDTH => 16, INIT_FILE => "")
    port map (clk => clk, cs => s_cs, we => s_we, addr => s_addr,
              din => s_din, dout => s_dout, addr_b => (others => '0'),
              dout_b => open);

  stim : process
    type shadow_t is array (0 to 2**AW - 1) of std_logic_vector(15 downto 0);
    variable shadow : shadow_t := (others => (others => '0'));
    variable seed   : unsigned(31 downto 0) := x"A11CE000";
    variable ra     : std_logic_vector(AW - 1 downto 0);
    variable rd     : std_logic_vector(15 downto 0);
    variable rop    : std_logic_vector(3 downto 0);
    variable lat    : natural;
    variable n_rd, n_wr : natural := 0;
    variable st0    : natural;
  begin
    wait for 2 * T;
    wait until falling_edge(clk);
    rst <= '0';
    wait until falling_edge(clk);
    for k in 1 to N_OPS loop
      lcg_rand(seed, ra);
      lcg_rand(seed, rd);
      lcg_rand(seed, rop);
      req   <= '1';
      we    <= '1' when unsigned(rop) < 6 else '0';
      addr  <= ra;
      wdata <= rd;
      st0   := strobes;
      lat   := 0;
      loop
        wait until rising_edge(clk);
        lat := lat + 1;
        exit when ready = '1';
        chk.check(lat <= WAIT_STATES + 2, "ready timeout");
        exit when lat > WAIT_STATES + 2;
      end loop;
      chk.check(lat = WAIT_STATES + 2,
                "latency " & integer'image(lat) & " (edge count incl. accept)");
      if we = '1' then
        shadow(to_integer(unsigned(ra))) := rd;
        n_wr := n_wr + 1;
      else
        chk.check_eq(rdata, shadow(to_integer(unsigned(ra))),
                     "read addr 0x" & to_hstring(ra));
        n_rd := n_rd + 1;
      end if;
      wait until falling_edge(clk);
      chk.check(strobes = st0 + 1, "exactly one SRAM strobe per request");
      req <= '0';
      -- random idle gap of 0-1 cycles (0 tests back-to-back requests)
      if rop(0) = '1' then
        wait until falling_edge(clk);
      end if;
    end loop;
    report "tb_sram_ctrl: WAIT_STATES=" & integer'image(WAIT_STATES) &
           " reads=" & integer'image(n_rd) & " writes=" & integer'image(n_wr);
    chk.summary("tb_sram_ctrl_ws" & integer'image(WAIT_STATES), cycles);
    done <= true;
    std.env.finish;
  end process;

end architecture sim;
