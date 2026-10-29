-- uart_ctrl.vhd
-- Memory-mapped UART controller: baud generator, TX/RX engines and an
-- 8-entry FIFO in each direction.
--
-- Register map (word addresses relative to the peripheral base):
--   0 DATA   W: push byte into TX FIFO      R: pop byte from RX FIFO
--   1 STATUS R: [0] tx_full [1] tx_empty [2] rx_avail [3] frame_err (sticky)
--               [4] tx_idle (FIFO empty and shifter idle) [5] rx_overrun (sticky)
--            W: any write clears the sticky error bits
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_ctrl is
  generic (
    BAUD_DIVISOR : positive := 54;
    FIFO_AW      : positive := 3
  );
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;
    -- register bus (single-cycle access)
    sel     : in  std_logic;
    we      : in  std_logic;
    addr    : in  std_logic;
    wdata   : in  std_logic_vector(7 downto 0);
    rdata   : out std_logic_vector(15 downto 0);
    -- serial pins
    rxd     : in  std_logic;
    txd     : out std_logic;
    tx_idle : out std_logic
  );
end entity uart_ctrl;

architecture rtl of uart_ctrl is
  signal tick16                     : std_logic;
  signal tx_push, tx_pop            : std_logic;
  signal tx_dout                    : std_logic_vector(7 downto 0);
  signal tx_empty, tx_full, tx_busy : std_logic;
  signal rx_data                    : std_logic_vector(7 downto 0);
  signal rx_valid, rx_ferr          : std_logic;
  signal rx_pop, rx_push            : std_logic;
  signal rx_dout                    : std_logic_vector(7 downto 0);
  signal rx_empty, rx_full          : std_logic;
  signal ferr_sticky, ovr_sticky    : std_logic := '0';
  signal status                     : std_logic_vector(15 downto 0);
begin

  u_baud : entity work.baud_gen
    generic map (DIVISOR => BAUD_DIVISOR)
    port map (clk => clk, rst => rst, tick16 => tick16);

  -- TX path ---------------------------------------------------------------
  tx_push <= sel and we and not addr;

  u_txfifo : entity work.fifo
    generic map (DATA_WIDTH => 8, ADDR_WIDTH => FIFO_AW)
    port map (clk => clk, rst => rst, push => tx_push, din => wdata,
              pop => tx_pop, dout => tx_dout, empty => tx_empty,
              full => tx_full, count => open);

  tx_pop <= not tx_empty and not tx_busy;

  u_tx : entity work.uart_tx
    port map (clk => clk, rst => rst, tick16 => tick16, start => tx_pop,
              data => tx_dout, busy => tx_busy, done => open, txd => txd);

  -- RX path ---------------------------------------------------------------
  u_rx : entity work.uart_rx
    port map (clk => clk, rst => rst, tick16 => tick16, rxd => rxd,
              data => rx_data, valid => rx_valid, frame_err => rx_ferr);

  rx_push <= rx_valid;
  rx_pop  <= sel and not we and not addr;

  u_rxfifo : entity work.fifo
    generic map (DATA_WIDTH => 8, ADDR_WIDTH => FIFO_AW)
    port map (clk => clk, rst => rst, push => rx_push, din => rx_data,
              pop => rx_pop, dout => rx_dout, empty => rx_empty,
              full => rx_full, count => open);

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        ferr_sticky <= '0';
        ovr_sticky  <= '0';
      elsif sel = '1' and we = '1' and addr = '1' then
        ferr_sticky <= '0';
        ovr_sticky  <= '0';
      else
        if rx_ferr = '1' then
          ferr_sticky <= '1';
        end if;
        if rx_valid = '1' and rx_full = '1' and rx_pop = '0' then
          ovr_sticky <= '1';
        end if;
      end if;
    end if;
  end process;

  status <= (0 => tx_full, 1 => tx_empty, 2 => not rx_empty,
             3 => ferr_sticky, 4 => tx_empty and not tx_busy,
             5 => ovr_sticky, others => '0');

  rdata   <= status when addr = '1' else x"00" & rx_dout;
  tx_idle <= tx_empty and not tx_busy;

end architecture rtl;
