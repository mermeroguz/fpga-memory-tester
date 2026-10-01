-- tester_pkg.vhd
-- Test patterns and small helpers shared across the design.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package tester_pkg is
  constant ADDR_W       : integer := 10;   -- 1024 memory words
  constant NUM_PATTERNS : integer := 6;

  -- pattern 0: all zeros            (stuck-at-1 bits show up)
  -- pattern 1: all ones             (stuck-at-0 bits show up)
  -- pattern 2: checkerboard 55/AA   (adjacent bits shorted together)
  -- pattern 3: inverse checkerboard
  -- pattern 4: address-in-address   (address decoder faults / aliasing)
  -- pattern 5: walking ones         (each bit line toggled on its own)
  function expected_data(pattern : integer;
                         addr    : unsigned(ADDR_W - 1 downto 0))
    return std_logic_vector;

  -- 4-bit value -> ASCII '0'..'9','A'..'F'
  function hex_char(n : std_logic_vector(3 downto 0)) return std_logic_vector;
end package;

package body tester_pkg is

  function expected_data(pattern : integer;
                         addr    : unsigned(ADDR_W - 1 downto 0))
    return std_logic_vector is
    variable d : std_logic_vector(7 downto 0);
  begin
    case pattern is
      when 0 => d := x"00";
      when 1 => d := x"FF";
      when 2 =>
        if addr(0) = '0' then d := x"55"; else d := x"AA"; end if;
      when 3 =>
        if addr(0) = '0' then d := x"AA"; else d := x"55"; end if;
      when 4 =>
        -- fold the top address bits in so all 1024 words differ from neighbors
        d := std_logic_vector(addr(7 downto 0) xor resize(addr(ADDR_W - 1 downto 8), 8));
      when others =>
        d := (others => '0');
        d(to_integer(addr(2 downto 0))) := '1';
    end case;
    return d;
  end function;

  function hex_char(n : std_logic_vector(3 downto 0)) return std_logic_vector is
    variable v : integer range 0 to 15;
  begin
    v := to_integer(unsigned(n));
    if v < 10 then
      return std_logic_vector(to_unsigned(48 + v, 8));   -- '0' = 48
    else
      return std_logic_vector(to_unsigned(55 + v, 8));   -- 'A' = 65 = 55 + 10
    end if;
  end function;

end package body;
