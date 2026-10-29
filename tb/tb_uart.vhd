-- tb_uart.vhd
-- UART TX/RX verification:
--   1. TX -> RX loopback of all 256 byte values through the RTL blocks.
--   2. An independent behavioural receiver samples the TX line at bit
--      centres and checks start/stop bits and the measured bit period.
--   3. A behavioural transmitter drives the RX input with +/-3 % baud
--      error and checks the received byte.
--   4. A frame with a low stop bit must raise frame_err and not valid.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tb_pkg.all;

entity tb_uart is
  generic (DIVISOR : positive := 2);
end entity tb_uart;

architecture sim of tb_uart is
  constant T        : time := 10 ns;
  constant BIT_CLKS : positive := 16 * DIVISOR;
  constant BIT_T    : time := BIT_CLKS * T;
  signal clk  : std_logic := '0';
  signal rst  : std_logic := '1';
  signal done : boolean := false;
  signal cycles : natural := 0;
  signal tick16 : std_logic;
  signal tx_start, tx_busy, tx_done, txd : std_logic := '0';
  signal tx_data   : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_line   : std_logic := '1';
  signal ext_line  : std_logic := '1';
  signal use_ext   : boolean := false;
  signal rx_data   : std_logic_vector(7 downto 0);
  signal rx_valid, rx_ferr : std_logic;
  signal mon_byte  : std_logic_vector(7 downto 0) := (others => '0');
  signal mon_count : natural := 0;
  signal rx_count, ferr_count : natural := 0;
  signal last_rx   : std_logic_vector(7 downto 0) := (others => '0');
  shared variable chk : checker_t;
begin

  clk <= not clk after T / 2 when not done;
  process (clk) begin
    if rising_edge(clk) then cycles <= cycles + 1; end if;
  end process;

  u_baud : entity work.baud_gen
    generic map (DIVISOR => DIVISOR)
    port map (clk => clk, rst => rst, tick16 => tick16);

  u_tx : entity work.uart_tx
    port map (clk => clk, rst => rst, tick16 => tick16, start => tx_start,
              data => tx_data, busy => tx_busy, done => tx_done, txd => txd);

  rx_line <= ext_line when use_ext else txd;

  u_rx : entity work.uart_rx
    port map (clk => clk, rst => rst, tick16 => tick16, rxd => rx_line,
              data => rx_data, valid => rx_valid, frame_err => rx_ferr);

  -- Collect RX results
  process (clk)
  begin
    if rising_edge(clk) then
      if rx_valid = '1' then
        rx_count <= rx_count + 1;
        last_rx  <= rx_data;
      end if;
      if rx_ferr = '1' then
        ferr_count <= ferr_count + 1;
      end if;
    end if;
  end process;

  -- Independent line monitor on txd
  monitor : process
    variable t0 : time;
    variable b  : std_logic_vector(7 downto 0);
  begin
    wait until falling_edge(txd);
    t0 := now;
    wait for BIT_T / 2;
    chk.check(txd = '0', "monitor: start bit low at centre");
    for i in 0 to 7 loop
      wait for BIT_T;
      b(i) := txd;
    end loop;
    wait for BIT_T;
    chk.check(txd = '1', "monitor: stop bit high at centre");
    mon_byte  <= b;
    mon_count <= mon_count + 1;
    -- Bit period: the start-bit edge must arrive no later than one 16x
    -- tick after the transmitter was started; total frame ~10 bits.
    wait until txd = '1' and tx_busy = '0';
    chk.check(now - t0 >= 10 * BIT_T - BIT_T / 16 and
              now - t0 <= 10 * BIT_T + BIT_T / 8,
              "monitor: frame length " & time'image(now - t0));
  end process;

  stim : process
    procedure send_ext(byte : std_logic_vector(7 downto 0); err_ppm : integer;
                       stop_bit : std_logic) is
      variable bt : time;
    begin
      bt := BIT_T + (BIT_T / 1000000) * err_ppm;
      ext_line <= '0';
      wait for bt;
      for i in 0 to 7 loop
        ext_line <= byte(i);
        wait for bt;
      end loop;
      ext_line <= stop_bit;
      wait for bt;
      ext_line <= '1';
      wait for 2 * bt;
    end procedure;
    variable seed : unsigned(31 downto 0) := x"5EED0001";
    variable rb   : std_logic_vector(7 downto 0);
    variable rc   : natural;
    type err_list_t is array (natural range <>) of integer;
    constant ERRS : err_list_t := (-30000, -15000, 0, 15000, 30000);
  begin
    wait for 3 * T;
    wait until falling_edge(clk);
    rst <= '0';
    wait for 5 * T;

    -- 1+2: loopback of every byte value
    for v in 0 to 255 loop
      wait until falling_edge(clk);
      tx_data  <= std_logic_vector(to_unsigned(v, 8));
      tx_start <= '1';
      wait until falling_edge(clk);
      tx_start <= '0';
      chk.check(tx_busy = '1', "tx busy after start");
      wait until tx_done = '1';
      wait for 4 * BIT_T / 16;  -- let the RX finish the stop-bit sample
      chk.check(rx_count = v + 1, "loopback count " & integer'image(v));
      chk.check_eq(last_rx, std_logic_vector(to_unsigned(v, 8)), "loopback data");
      chk.check_eq(mon_byte, std_logic_vector(to_unsigned(v, 8)), "monitor data");
    end loop;
    chk.check(ferr_count = 0, "no frame errors in loopback");

    -- 3: baud-rate tolerance on the receiver
    if tx_busy = '1' then
      wait until tx_busy = '0';
    end if;
    use_ext <= true;
    wait for BIT_T;
    for e in ERRS'range loop
      for k in 1 to 8 loop
        lcg_rand(seed, rb);
        rc := rx_count;
        send_ext(rb, ERRS(e), '1');
        chk.check(rx_count = rc + 1, "rx with baud error " & integer'image(ERRS(e)) & " ppm");
        chk.check_eq(last_rx, rb, "rx data with baud error");
      end loop;
    end loop;

    -- 4: framing error
    rc := rx_count;
    send_ext(x"A5", 0, '0');
    chk.check(ferr_count = 1, "frame error detected");
    chk.check(rx_count = rc, "no valid on bad stop bit");
    -- receiver recovers on the next good frame
    send_ext(x"3C", 0, '1');
    chk.check(rx_count = rc + 1, "recovery after frame error");
    chk.check_eq(last_rx, x"3C", "recovery data");

    chk.summary("tb_uart", cycles);
    done <= true;
    std.env.finish;
  end process;

end architecture sim;
