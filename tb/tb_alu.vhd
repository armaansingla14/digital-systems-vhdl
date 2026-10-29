-- tb_alu.vhd
-- Directed corner cases plus pseudo-random vectors for every ALU op,
-- checked against an independent reference written with integer arithmetic.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu_pkg.all;
use work.tb_pkg.all;

entity tb_alu is
  generic (N_RANDOM : natural := 3000);
end entity tb_alu;

architecture sim of tb_alu is
  signal a, b, y : word_t := (others => '0');
  signal op      : alu_op_t := ALU_ADD;
  signal zero, neg, carry, ovf : std_logic;
  shared variable chk : checker_t;

  type op_list_t is array (natural range <>) of alu_op_t;
  constant OPS : op_list_t := (ALU_ADD, ALU_SUB, ALU_AND, ALU_OR, ALU_XOR,
                               ALU_SLT, ALU_SLL, ALU_SRL, ALU_PASB, ALU_LLI);

  function ref(av, bv : word_t; o : alu_op_t) return word_t is
    variable ai, bi, r : integer;
    variable sh        : natural;
  begin
    ai := to_integer(unsigned(av));
    bi := to_integer(unsigned(bv));
    sh := bi mod 16;
    case o is
      when ALU_ADD  => r := (ai + bi) mod 65536;
      when ALU_SUB  => r := (ai - bi + 65536) mod 65536;
      when ALU_AND  => return av and bv;
      when ALU_OR   => return av or bv;
      when ALU_XOR  => return av xor bv;
      when ALU_SLT  =>
        if to_integer(signed(av)) < to_integer(signed(bv)) then r := 1; else r := 0; end if;
      when ALU_SLL  => r := (ai * 2**sh) mod 65536;
      when ALU_SRL  => r := ai / 2**sh;
      when ALU_PASB => r := bi;
      when ALU_LLI  => r := (ai / 256) * 256 + (bi mod 256);
      when others   => r := 0;
    end case;
    return std_logic_vector(to_unsigned(r, 16));
  end function;

begin

  dut : entity work.alu
    port map (a => a, b => b, op => op, y => y, zero => zero,
              negative => neg, carry => carry, overflow => ovf);

  stim : process
    variable seed   : unsigned(31 downto 0) := x"1234ABCD";
    variable ra, rb : std_logic_vector(15 downto 0);
    variable ridx   : std_logic_vector(3 downto 0);
    variable exp    : word_t;
    variable s17    : integer;
    variable n_vec  : natural := 0;

    procedure apply(av, bv : word_t; o : alu_op_t) is
      variable sa, sb, sr : integer;
    begin
      a <= av; b <= bv; op <= o;
      wait for 1 ns;
      exp := ref(av, bv, o);
      chk.check_eq(y, exp, "op=" & to_hstring(o) & " a=" & to_hstring(av) &
                           " b=" & to_hstring(bv));
      chk.check((zero = '1') = (exp = x"0000"), "zero flag");
      chk.check(neg = exp(15), "negative flag");
      sa := to_integer(signed(av));
      sb := to_integer(signed(bv));
      if o = ALU_ADD then
        sr := sa + sb;
        chk.check((ovf = '1') = (sr > 32767 or sr < -32768), "add overflow");
        s17 := to_integer(unsigned(av)) + to_integer(unsigned(bv));
        chk.check((carry = '1') = (s17 > 65535), "add carry");
      elsif o = ALU_SUB then
        sr := sa - sb;
        chk.check((ovf = '1') = (sr > 32767 or sr < -32768), "sub overflow");
        chk.check((carry = '1') = (unsigned(av) < unsigned(bv)), "sub borrow");
      end if;
      n_vec := n_vec + 1;
    end procedure;

    type corner_t is array (natural range <>) of word_t;
    constant CORNERS : corner_t := (x"0000", x"0001", x"7FFF", x"8000",
                                    x"FFFF", x"00FF", x"FF00", x"5555", x"000F");
  begin
    -- Directed: every op over all corner pairs
    for k in OPS'range loop
      for i in CORNERS'range loop
        for j in CORNERS'range loop
          apply(CORNERS(i), CORNERS(j), OPS(k));
        end loop;
      end loop;
    end loop;
    -- Random
    for n in 1 to N_RANDOM loop
      lcg_rand(seed, ra);
      lcg_rand(seed, rb);
      lcg_rand(seed, ridx);
      apply(ra, rb, OPS(to_integer(unsigned(ridx)) mod OPS'length));
    end loop;
    report "tb_alu: applied " & integer'image(n_vec) & " vectors";
    chk.summary("tb_alu", 0);
    std.env.finish;
  end process;

end architecture sim;
