-- seg7_mux.vhd
-- Drives the Nexys4 DDR's 8-digit 7-segment display with a 32-bit hex value.
-- Only one digit is lit at a time; switching fast (~760 Hz per step,
-- ~95 Hz per digit) makes all 8 look lit to the eye.
-- Segments and anodes are active low on this board.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity seg7_mux is
  port (
    clk   : in  std_logic;
    value : in  std_logic_vector(31 downto 0);
    seg   : out std_logic_vector(6 downto 0);   -- seg(0)=CA ... seg(6)=CG
    an    : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of seg7_mux is
  signal refresh : unsigned(19 downto 0) := (others => '0');
  signal seg_r   : std_logic_vector(6 downto 0) := (others => '1');
  signal an_r    : std_logic_vector(7 downto 0) := (others => '1');
begin

  process (clk)
    variable sel : integer range 0 to 7;
    variable nib : std_logic_vector(3 downto 0);
  begin
    if rising_edge(clk) then
      refresh <= refresh + 1;
      sel := to_integer(refresh(19 downto 17));

      nib := (others => '0');
      for i in 0 to 7 loop
        if sel = i then
          nib := value(i * 4 + 3 downto i * 4);
        end if;
      end loop;

      an_r      <= (others => '1');
      an_r(sel) <= '0';

      case nib is                 --  gfedcba
        when x"0"   => seg_r <= "1000000";
        when x"1"   => seg_r <= "1111001";
        when x"2"   => seg_r <= "0100100";
        when x"3"   => seg_r <= "0110000";
        when x"4"   => seg_r <= "0011001";
        when x"5"   => seg_r <= "0010010";
        when x"6"   => seg_r <= "0000010";
        when x"7"   => seg_r <= "1111000";
        when x"8"   => seg_r <= "0000000";
        when x"9"   => seg_r <= "0010000";
        when x"A"   => seg_r <= "0001000";
        when x"B"   => seg_r <= "0000011";
        when x"C"   => seg_r <= "1000110";
        when x"D"   => seg_r <= "0100001";
        when x"E"   => seg_r <= "0000110";
        when others => seg_r <= "0001110";   -- F
      end case;
    end if;
  end process;

  seg <= seg_r;
  an  <= an_r;

end architecture;
