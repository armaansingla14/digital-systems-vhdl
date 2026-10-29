-- sram_ctrl.vhd
-- Bridges the CPU request/ready bus onto a synchronous SRAM port. The SRAM
-- is strobed in the request cycle; 'ready' is returned WAIT_STATES + 1
-- cycles later, which models slower external memories while leaving the
-- CPU protocol unchanged.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sram_ctrl is
  generic (
    ADDR_WIDTH  : positive := 12;
    DATA_WIDTH  : positive := 16;
    WAIT_STATES : natural  := 0
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    -- bus side
    req       : in  std_logic;
    we        : in  std_logic;
    addr      : in  std_logic_vector(ADDR_WIDTH - 1 downto 0);
    wdata     : in  std_logic_vector(DATA_WIDTH - 1 downto 0);
    rdata     : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    ready     : out std_logic;
    -- SRAM side
    sram_cs   : out std_logic;
    sram_we   : out std_logic;
    sram_addr : out std_logic_vector(ADDR_WIDTH - 1 downto 0);
    sram_din  : out std_logic_vector(DATA_WIDTH - 1 downto 0);
    sram_dout : in  std_logic_vector(DATA_WIDTH - 1 downto 0)
  );
end entity sram_ctrl;

architecture rtl of sram_ctrl is
  type state_t is (IDLE, WAITING, DONE);
  signal state : state_t := IDLE;
  signal wcnt  : natural range 0 to WAIT_STATES := 0;
begin

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state <= IDLE;
        wcnt  <= 0;
      else
        case state is
          when IDLE =>
            if req = '1' then
              if WAIT_STATES = 0 then
                state <= DONE;
              else
                wcnt  <= 0;
                state <= WAITING;
              end if;
            end if;
          when WAITING =>
            if wcnt = WAIT_STATES - 1 then
              state <= DONE;
            else
              wcnt <= wcnt + 1;
            end if;
          when DONE =>
            state <= IDLE;
        end case;
      end if;
    end if;
  end process;

  -- The SRAM is only enabled in the cycle the request is accepted, so its
  -- output register holds the read data until 'ready'.
  sram_cs   <= req when state = IDLE else '0';
  sram_we   <= we;
  sram_addr <= addr;
  sram_din  <= wdata;
  rdata     <= sram_dout;
  ready     <= '1' when state = DONE else '0';

end architecture rtl;
