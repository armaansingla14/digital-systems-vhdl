-- tb_soc.vhd
-- Runs an assembled program on the full SoC (CPU + SRAM controller + UART).
-- The testbench drives UART_IN into the RX pin, decodes the TX pin with a
-- behavioural receiver, waits for HALT and for the UART to drain, then
-- writes a state dump (registers, RAM window, UART bytes, counters) that
-- tools/iss.py compares against the instruction-set simulator.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.cpu_pkg.all;
use work.tb_pkg.all;

entity tb_soc is
  generic (
    PROG_FILE    : string   := "build/fib.hex";
    DUMP_FILE    : string   := "build/fib.dump";
    TB_NAME      : string   := "tb_soc";
    UART_IN      : string   := "";
    WAIT_STATES  : natural  := 0;
    BAUD_DIVISOR : positive := 1;
    MAX_CYCLES   : positive := 200000;
    DUMP_WORDS   : positive := 1024
  );
end entity tb_soc;

architecture sim of tb_soc is
  constant T     : time := 10 ns;
  constant BIT_T : time := 16 * BAUD_DIVISOR * T;
  signal clk     : std_logic := '0';
  signal rst     : std_logic := '1';
  signal done    : boolean := false;
  signal sim_cycles : natural := 0;
  signal rxd, txd : std_logic := '1';
  signal leds    : std_logic_vector(15 downto 0);
  signal halted, illegal, uart_idle : std_logic;
  signal cycles, instret : std_logic_vector(31 downto 0);
  signal dbg_reg   : reg_addr_t := "000";
  signal dbg_rdata : word_t;
  signal dbg_maddr : std_logic_vector(11 downto 0) := (others => '0');
  signal dbg_mdata, dbg_pc : word_t;

  type byte_buf_t is array (0 to 1023) of std_logic_vector(7 downto 0);
  signal tx_bytes : byte_buf_t;
  signal tx_count : natural := 0;
  signal rx_sent  : boolean := false;
  shared variable chk : checker_t;
begin

  clk <= not clk after T / 2 when not done;
  process (clk) begin
    if rising_edge(clk) then sim_cycles <= sim_cycles + 1; end if;
  end process;

  dut : entity work.soc_top
    generic map (INIT_FILE => PROG_FILE, WAIT_STATES => WAIT_STATES,
                 BAUD_DIVISOR => BAUD_DIVISOR)
    port map (clk => clk, rst => rst, uart_rxd => rxd, uart_txd => txd,
              leds => leds, switches => x"A5A5", halted => halted,
              illegal => illegal, uart_idle => uart_idle, cycles => cycles,
              instret => instret, dbg_reg => dbg_reg, dbg_rdata => dbg_rdata,
              dbg_maddr => dbg_maddr, dbg_mdata => dbg_mdata, dbg_pc => dbg_pc);

  -- Behavioural UART receiver on the TX pin
  uart_mon : process
    variable b : std_logic_vector(7 downto 0);
  begin
    wait until falling_edge(txd);
    wait for BIT_T / 2;
    chk.check(txd = '0', "tx start bit");
    for i in 0 to 7 loop
      wait for BIT_T;
      b(i) := txd;
    end loop;
    wait for BIT_T;
    chk.check(txd = '1', "tx stop bit");
    tx_bytes(tx_count) <= b;
    tx_count <= tx_count + 1;
  end process;

  -- Behavioural UART transmitter into the RX pin
  uart_drv : process
    variable c : std_logic_vector(7 downto 0);
  begin
    wait until rst = '0';
    wait for 20 * T;
    for k in UART_IN'range loop
      c := std_logic_vector(to_unsigned(character'pos(UART_IN(k)), 8));
      rxd <= '0';
      wait for BIT_T;
      for i in 0 to 7 loop
        rxd <= c(i);
        wait for BIT_T;
      end loop;
      rxd <= '1';
      wait for 2 * BIT_T;
    end loop;
    rx_sent <= true;
    wait;
  end process;

  main : process
    file f      : text;
    variable l  : line;
    variable st : file_open_status;
    variable n  : natural := 0;
  begin
    wait for 4 * T;
    wait until falling_edge(clk);
    rst <= '0';
    while halted /= '1' and n < MAX_CYCLES loop
      wait until falling_edge(clk);
      n := n + 1;
    end loop;
    chk.check(halted = '1', "program halted within " & integer'image(MAX_CYCLES) & " cycles");
    chk.check(illegal = '0', "no illegal opcode");
    -- let the UART drain (CPU programs normally wait for this themselves)
    n := 0;
    while uart_idle /= '1' and n < 100000 loop
      wait until falling_edge(clk);
      n := n + 1;
    end loop;
    wait for 2 * BIT_T;
    if UART_IN'length > 0 then
      chk.check(rx_sent, "all UART input was consumed before halt");
    end if;

    file_open(st, f, DUMP_FILE, write_mode);
    assert st = open_ok report "cannot open dump file " & DUMP_FILE severity failure;
    for i in 0 to 7 loop
      dbg_reg <= std_logic_vector(to_unsigned(i, 3));
      wait for 1 ns;
      write(l, string'("R ") & integer'image(i) & " " & to_hstring(dbg_rdata));
      writeline(f, l);
    end loop;
    for a in 0 to DUMP_WORDS - 1 loop
      dbg_maddr <= std_logic_vector(to_unsigned(a, 12));
      wait until falling_edge(clk);
      wait until falling_edge(clk);
      write(l, string'("M ") & to_hstring(dbg_maddr) & " " & to_hstring(dbg_mdata));
      writeline(f, l);
    end loop;
    for i in 0 to tx_count - 1 loop
      write(l, string'("U ") & to_hstring(tx_bytes(i)));
      writeline(f, l);
    end loop;
    write(l, string'("CYCLES ") & integer'image(to_integer(unsigned(cycles))));
    writeline(f, l);
    write(l, string'("INSTRET ") & integer'image(to_integer(unsigned(instret))));
    writeline(f, l);
    write(l, string'("HALTED ") & std_logic'image(halted)(2));
    writeline(f, l);
    write(l, string'("PC ") & to_hstring(dbg_pc));
    writeline(f, l);
    write(l, string'("LEDS ") & to_hstring(leds));
    writeline(f, l);
    file_close(f);

    report TB_NAME & ": cpu_cycles=" & integer'image(to_integer(unsigned(cycles))) &
           " instret=" & integer'image(to_integer(unsigned(instret))) &
           " uart_bytes=" & integer'image(tx_count);
    chk.summary(TB_NAME, sim_cycles);
    done <= true;
    std.env.finish;
  end process;

end architecture sim;
