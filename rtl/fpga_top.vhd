-- fpga_top.vhd
-- Board wrapper for a Basys3 / Arty-class board (100 MHz oscillator).
-- Synchronises the reset button, maps LEDs/switches and the USB-UART pins.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fpga_top is
  generic (
    INIT_FILE    : string   := "programs/hello.hex";
    BAUD_DIVISOR : positive := 54   -- 100 MHz / (16 * 115200)
  );
  port (
    clk100 : in  std_logic;
    btn_rst: in  std_logic;
    sw     : in  std_logic_vector(15 downto 0);
    led    : out std_logic_vector(15 downto 0);
    uart_rx: in  std_logic;
    uart_tx: out std_logic
  );
end entity fpga_top;

architecture rtl of fpga_top is
  signal rst_sync : std_logic_vector(2 downto 0) := (others => '1');
  signal rst      : std_logic;
  signal halted   : std_logic;
  signal leds_i   : std_logic_vector(15 downto 0);
begin

  process (clk100)
  begin
    if rising_edge(clk100) then
      rst_sync <= rst_sync(1 downto 0) & btn_rst;
    end if;
  end process;
  rst <= rst_sync(2);

  u_soc : entity work.soc_top
    generic map (INIT_FILE => INIT_FILE, WAIT_STATES => 0,
                 BAUD_DIVISOR => BAUD_DIVISOR)
    port map (clk => clk100, rst => rst, uart_rxd => uart_rx,
              uart_txd => uart_tx, leds => leds_i, switches => sw,
              halted => halted, illegal => open, uart_idle => open,
              cycles => open, instret => open, dbg_reg => "000",
              dbg_rdata => open, dbg_maddr => (others => '0'),
              dbg_mdata => open, dbg_pc => open);

  -- LED15 shows the halt state; the rest mirror the LED register.
  led <= halted & leds_i(14 downto 0);

end architecture rtl;
