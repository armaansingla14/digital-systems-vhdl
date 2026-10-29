-- tb_pkg.vhd
-- Self-checking helpers shared by all testbenches. Each testbench owns a
-- shared checker; at the end it prints a single machine-readable line:
--   TB_RESULT <name> checks=<n> failures=<n> cycles=<n> status=<PASS|FAIL>
-- which scripts/run_tests.py collects into results/.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

package tb_pkg is

  type checker_t is protected
    procedure check(cond : boolean; msg : string);
    procedure check_eq(got, exp : std_logic_vector; msg : string);
    impure function checks return natural;
    impure function failures return natural;
    procedure summary(name : string; cycles : natural);
  end protected checker_t;

  -- Simple LCG so testbenches are reproducible without math_real seeds.
  procedure lcg_next(variable state : inout unsigned(31 downto 0));
  -- Fill 'v' (up to 32 bits) with the next pseudo-random value.
  procedure lcg_rand(variable state : inout unsigned(31 downto 0);
                     variable v : out std_logic_vector);

end package tb_pkg;

package body tb_pkg is

  type checker_t is protected body
    variable n_checks : natural := 0;
    variable n_fail   : natural := 0;

    procedure check(cond : boolean; msg : string) is
    begin
      n_checks := n_checks + 1;
      if not cond then
        n_fail := n_fail + 1;
        if n_fail <= 20 then
          report "CHECK FAILED: " & msg severity error;
        end if;
      end if;
    end procedure;

    procedure check_eq(got, exp : std_logic_vector; msg : string) is
    begin
      check(got = exp, msg & " got=0x" & to_hstring(got) &
                       " exp=0x" & to_hstring(exp));
    end procedure;

    impure function checks return natural is
    begin
      return n_checks;
    end function;

    impure function failures return natural is
    begin
      return n_fail;
    end function;

    procedure summary(name : string; cycles : natural) is
      variable l : line;
    begin
      write(l, string'("TB_RESULT ") & name & " checks=" & integer'image(n_checks) &
               " failures=" & integer'image(n_fail) &
               " cycles=" & integer'image(cycles));
      if n_fail = 0 and n_checks > 0 then
        write(l, string'(" status=PASS"));
      else
        write(l, string'(" status=FAIL"));
      end if;
      writeline(output, l);
      assert n_fail = 0 report name & " had failures" severity failure;
    end procedure;
  end protected body checker_t;

  procedure lcg_next(variable state : inout unsigned(31 downto 0)) is
    variable p : unsigned(63 downto 0);
  begin
    p     := state * to_unsigned(1664525, 32);
    state := p(31 downto 0) + to_unsigned(1013904223, 32);
  end procedure;

  procedure lcg_rand(variable state : inout unsigned(31 downto 0);
                     variable v : out std_logic_vector) is
  begin
    lcg_next(state);
    -- take the high bits, which have the longest period in an LCG
    v := std_logic_vector(state(31 downto 32 - v'length));
  end procedure;

end package body tb_pkg;
