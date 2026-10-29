-- soc_top.vhd
-- CPU + synchronous SRAM (via sram_ctrl) + memory-mapped peripherals.
--
-- Address map (16-bit word addresses):
--   0x0000-0x0FFF  RAM (4K x 16, program and data)
--   0xFF00         UART DATA
--   0xFF01         UART STATUS
--   0xFF02         LED register (R/W)
--   0xFF03         switch inputs (R)
--   0xFF04         cycle counter, low 16 bits (R)
-- Any other address reads as zero and completes in one cycle.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu_pkg.all;

entity soc_top is
  generic (
    INIT_FILE    : string   := "";
    WAIT_STATES  : natural  := 0;
    BAUD_DIVISOR : positive := 54
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    uart_rxd  : in  std_logic;
    uart_txd  : out std_logic;
    leds      : out std_logic_vector(15 downto 0);
    switches  : in  std_logic_vector(15 downto 0);
    halted    : out std_logic;
    illegal   : out std_logic;
    -- debug / verification ports
    uart_idle : out std_logic;
    cycles    : out std_logic_vector(31 downto 0);
    instret   : out std_logic_vector(31 downto 0);
    dbg_reg   : in  reg_addr_t;
    dbg_rdata : out word_t;
    dbg_maddr : in  std_logic_vector(11 downto 0);
    dbg_mdata : out word_t;
    dbg_pc    : out word_t
  );
end entity soc_top;

architecture rtl of soc_top is
  signal mem_req, mem_we, mem_ready : std_logic;
  signal mem_addr, mem_wdata        : word_t;
  signal mem_rdata                  : word_t;
  signal ram_sel, io_sel            : std_logic;
  signal ram_req, ram_ready         : std_logic;
  signal ram_rdata                  : word_t;
  signal sram_cs, sram_we           : std_logic;
  signal sram_addr                  : std_logic_vector(11 downto 0);
  signal sram_din, sram_dout        : word_t;
  signal uart_sel                   : std_logic;
  signal uart_rdata                 : word_t;
  signal led_r                      : word_t := (others => '0');
  signal io_rdata                   : word_t;
  signal cycles_i                   : std_logic_vector(31 downto 0);
begin

  u_cpu : entity work.cpu
    port map (clk => clk, rst => rst, mem_req => mem_req, mem_we => mem_we,
              mem_addr => mem_addr, mem_wdata => mem_wdata,
              mem_rdata => mem_rdata, mem_ready => mem_ready,
              halted => halted, illegal => illegal, pc_dbg => dbg_pc,
              cycles => cycles_i, instret => instret,
              dbg_reg => dbg_reg, dbg_data => dbg_rdata);

  -- Address decode ----------------------------------------------------------
  ram_sel <= '1' when mem_addr(15 downto 12) = "0000" else '0';
  io_sel  <= not ram_sel;
  ram_req <= mem_req and ram_sel;

  u_ctrl : entity work.sram_ctrl
    generic map (ADDR_WIDTH => 12, DATA_WIDTH => 16, WAIT_STATES => WAIT_STATES)
    port map (clk => clk, rst => rst, req => ram_req, we => mem_we,
              addr => mem_addr(11 downto 0), wdata => mem_wdata,
              rdata => ram_rdata, ready => ram_ready,
              sram_cs => sram_cs, sram_we => sram_we, sram_addr => sram_addr,
              sram_din => sram_din, sram_dout => sram_dout);

  u_ram : entity work.sync_sram
    generic map (ADDR_WIDTH => 12, DATA_WIDTH => 16, INIT_FILE => INIT_FILE)
    port map (clk => clk, cs => sram_cs, we => sram_we, addr => sram_addr,
              din => sram_din, dout => sram_dout,
              addr_b => dbg_maddr, dout_b => dbg_mdata);

  -- Peripherals ---------------------------------------------------------------
  uart_sel <= '1' when mem_req = '1' and io_sel = '1' and
                       mem_addr(15 downto 1) = x"FF0" & "000" else '0';

  u_uart : entity work.uart_ctrl
    generic map (BAUD_DIVISOR => BAUD_DIVISOR)
    port map (clk => clk, rst => rst, sel => uart_sel, we => mem_we,
              addr => mem_addr(0), wdata => mem_wdata(7 downto 0),
              rdata => uart_rdata, rxd => uart_rxd, txd => uart_txd,
              tx_idle => uart_idle);

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        led_r <= (others => '0');
      elsif mem_req = '1' and mem_we = '1' and mem_addr = x"FF02" then
        led_r <= mem_wdata;
      end if;
    end if;
  end process;

  process (all)
  begin
    case mem_addr is
      when x"FF00" | x"FF01" => io_rdata <= uart_rdata;
      when x"FF02"           => io_rdata <= led_r;
      when x"FF03"           => io_rdata <= switches;
      when x"FF04"           => io_rdata <= cycles_i(15 downto 0);
      when others            => io_rdata <= (others => '0');
    end case;
  end process;

  mem_rdata <= ram_rdata when ram_sel = '1' else io_rdata;
  mem_ready <= ram_ready when ram_sel = '1' else mem_req;

  leds   <= led_r;
  cycles <= cycles_i;

end architecture rtl;
