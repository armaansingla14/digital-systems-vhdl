-- uart_tx.vhd
-- 8N1 UART transmitter driven by a 16x baud tick.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;
    tick16  : in  std_logic;
    start   : in  std_logic;
    data    : in  std_logic_vector(7 downto 0);
    busy    : out std_logic;
    done    : out std_logic;
    txd     : out std_logic
  );
end entity uart_tx;

architecture rtl of uart_tx is
  type state_t is (IDLE, START_BIT, DATA_BITS, STOP_BIT);
  signal state  : state_t := IDLE;
  signal shreg  : std_logic_vector(7 downto 0) := (others => '0');
  signal sub    : unsigned(3 downto 0) := (others => '0');
  signal bitn   : unsigned(2 downto 0) := (others => '0');
begin

  process (clk)
  begin
    if rising_edge(clk) then
      done <= '0';
      if rst = '1' then
        state <= IDLE;
        txd   <= '1';
        sub   <= (others => '0');
        bitn  <= (others => '0');
      else
        case state is
          when IDLE =>
            txd <= '1';
            if start = '1' then
              shreg <= data;
              sub   <= (others => '0');
              state <= START_BIT;
              txd   <= '0';
            end if;

          when START_BIT =>
            txd <= '0';
            if tick16 = '1' then
              if sub = 15 then
                sub   <= (others => '0');
                bitn  <= (others => '0');
                state <= DATA_BITS;
                txd   <= shreg(0);
              else
                sub <= sub + 1;
              end if;
            end if;

          when DATA_BITS =>
            txd <= shreg(0);
            if tick16 = '1' then
              if sub = 15 then
                sub   <= (others => '0');
                shreg <= '0' & shreg(7 downto 1);
                if bitn = 7 then
                  state <= STOP_BIT;
                  txd   <= '1';
                else
                  bitn <= bitn + 1;
                  txd  <= shreg(1);
                end if;
              else
                sub <= sub + 1;
              end if;
            end if;

          when STOP_BIT =>
            txd <= '1';
            if tick16 = '1' then
              if sub = 15 then
                sub   <= (others => '0');
                state <= IDLE;
                done  <= '1';
              else
                sub <= sub + 1;
              end if;
            end if;
        end case;
      end if;
    end if;
  end process;

  busy <= '0' when state = IDLE else '1';

end architecture rtl;
