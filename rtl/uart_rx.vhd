-- uart_rx.vhd
-- 8N1 UART receiver with 16x oversampling, two-flop input synchroniser,
-- start-bit validation at mid-bit and framing-error detection.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_rx is
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    tick16    : in  std_logic;
    rxd       : in  std_logic;
    data      : out std_logic_vector(7 downto 0);
    valid     : out std_logic;   -- one-cycle pulse, good stop bit
    frame_err : out std_logic    -- one-cycle pulse, stop bit was low
  );
end entity uart_rx;

architecture rtl of uart_rx is
  type state_t is (IDLE, START_BIT, DATA_BITS, STOP_BIT);
  signal state     : state_t := IDLE;
  signal sync      : std_logic_vector(1 downto 0) := "11";
  signal rx_s      : std_logic;
  signal sub       : unsigned(3 downto 0) := (others => '0');
  signal bitn      : unsigned(2 downto 0) := (others => '0');
  signal shreg     : std_logic_vector(7 downto 0) := (others => '0');
begin

  rx_s <= sync(1);

  process (clk)
  begin
    if rising_edge(clk) then
      sync      <= sync(0) & rxd;
      valid     <= '0';
      frame_err <= '0';
      if rst = '1' then
        state <= IDLE;
        sync  <= "11";
        sub   <= (others => '0');
      elsif tick16 = '1' then
        case state is
          when IDLE =>
            if rx_s = '0' then
              sub   <= (others => '0');
              state <= START_BIT;
            end if;

          when START_BIT =>
            -- Sample at the middle of the start bit to reject glitches.
            if sub = 7 then
              if rx_s = '0' then
                sub   <= (others => '0');
                bitn  <= (others => '0');
                state <= DATA_BITS;
              else
                state <= IDLE;
              end if;
            else
              sub <= sub + 1;
            end if;

          when DATA_BITS =>
            if sub = 15 then
              sub   <= (others => '0');
              shreg <= rx_s & shreg(7 downto 1);
              if bitn = 7 then
                state <= STOP_BIT;
              else
                bitn <= bitn + 1;
              end if;
            else
              sub <= sub + 1;
            end if;

          when STOP_BIT =>
            if sub = 15 then
              sub <= (others => '0');
              if rx_s = '1' then
                valid <= '1';
                state <= IDLE;
              else
                frame_err <= '1';
                state     <= IDLE;
              end if;
            else
              sub <= sub + 1;
            end if;
        end case;
      end if;
    end if;
  end process;

  data <= shreg;

end architecture rtl;
