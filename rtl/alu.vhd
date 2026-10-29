-- alu.vhd
-- 16-bit combinational ALU with status flags.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu_pkg.all;

entity alu is
  port (
    a        : in  word_t;
    b        : in  word_t;
    op       : in  alu_op_t;
    y        : out word_t;
    zero     : out std_logic;
    negative : out std_logic;
    carry    : out std_logic;
    overflow : out std_logic
  );
end entity alu;

architecture rtl of alu is
  signal result : word_t;
  signal sum17  : unsigned(XLEN downto 0);
  signal dif17  : unsigned(XLEN downto 0);
begin

  sum17 <= unsigned('0' & a) + unsigned('0' & b);
  dif17 <= unsigned('0' & a) - unsigned('0' & b);

  process (all)
    variable shamt : natural range 0 to 15;
  begin
    shamt := to_integer(unsigned(b(3 downto 0)));
    case op is
      when ALU_ADD  => result <= std_logic_vector(sum17(XLEN - 1 downto 0));
      when ALU_SUB  => result <= std_logic_vector(dif17(XLEN - 1 downto 0));
      when ALU_AND  => result <= a and b;
      when ALU_OR   => result <= a or b;
      when ALU_XOR  => result <= a xor b;
      when ALU_SLT  =>
        if signed(a) < signed(b) then
          result <= (0 => '1', others => '0');
        else
          result <= (others => '0');
        end if;
      when ALU_SLL  => result <= std_logic_vector(shift_left(unsigned(a), shamt));
      when ALU_SRL  => result <= std_logic_vector(shift_right(unsigned(a), shamt));
      when ALU_PASB => result <= b;
      when ALU_LLI  => result <= a(15 downto 8) & b(7 downto 0);
      when others   => result <= (others => '0');
    end case;
  end process;

  process (all)
  begin
    carry    <= '0';
    overflow <= '0';
    if op = ALU_ADD then
      carry    <= sum17(XLEN);
      overflow <= (a(15) xnor b(15)) and (a(15) xor sum17(15));
    elsif op = ALU_SUB then
      carry    <= dif17(XLEN);  -- borrow
      overflow <= (a(15) xor b(15)) and (a(15) xor dif17(15));
    end if;
  end process;

  y        <= result;
  zero     <= '1' when result = x"0000" else '0';
  negative <= result(15);

end architecture rtl;
