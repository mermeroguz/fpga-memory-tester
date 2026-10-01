-- secded_pkg.vhd
-- Hamming SECDED (Single Error Correct, Double Error Detect) for 8-bit data.
--
-- Codeword layout (13 bits):
--   bit 0        = overall parity (makes the whole codeword even parity)
--   bits 1..12   = classic Hamming(12,8) positions
--                  parity bits at positions 1, 2, 4, 8 (powers of two)
--                  data bits   at positions 3, 5, 6, 7, 9, 10, 11, 12
--
-- Key idea: each parity bit at position 2^k covers every position whose
-- index has bit k set. If exactly one bit flips, recomputing the parity
-- gives a "syndrome" equal to the flipped bit's position number.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package secded_pkg is
  subtype data_t is std_logic_vector(7 downto 0);
  subtype code_t is std_logic_vector(12 downto 0);

  type decode_t is record
    data          : data_t;
    corrected     : std_logic;  -- a single-bit error was found and fixed
    uncorrectable : std_logic;  -- a double-bit error was detected
  end record;

  function secded_encode(d : data_t) return code_t;
  function secded_decode(c : code_t) return decode_t;
end package;

package body secded_pkg is

  -- data bit i is stored at codeword position DATA_POS(i)
  type pos_array is array (0 to 7) of integer;
  constant DATA_POS : pos_array := (3, 5, 6, 7, 9, 10, 11, 12);

  function secded_encode(d : data_t) return code_t is
    variable c   : code_t := (others => '0');
    variable syn : unsigned(3 downto 0) := (others => '0');
    variable par : std_logic := '0';
  begin
    -- place data bits
    for i in 0 to 7 loop
      c(DATA_POS(i)) := d(i);
    end loop;
    -- XOR together the position numbers of all '1' data bits;
    -- that result tells us which parity bits must be set
    for pos in 1 to 12 loop
      if c(pos) = '1' then
        syn := syn xor to_unsigned(pos, 4);
      end if;
    end loop;
    c(1) := syn(0);
    c(2) := syn(1);
    c(4) := syn(2);
    c(8) := syn(3);
    -- overall parity over bits 1..12
    for pos in 1 to 12 loop
      par := par xor c(pos);
    end loop;
    c(0) := par;
    return c;
  end function;

  function secded_decode(c : code_t) return decode_t is
    variable fixed : code_t := c;
    variable syn   : unsigned(3 downto 0) := (others => '0');
    variable par   : std_logic := '0';
    variable r     : decode_t;
    variable p     : integer range 0 to 15;
  begin
    -- syndrome: XOR of positions holding a '1' (0 for a valid codeword)
    for pos in 1 to 12 loop
      if c(pos) = '1' then
        syn := syn xor to_unsigned(pos, 4);
      end if;
    end loop;
    -- overall parity over all 13 bits (0 for a valid codeword)
    for pos in 0 to 12 loop
      par := par xor c(pos);
    end loop;

    r.corrected     := '0';
    r.uncorrectable := '0';
    p := to_integer(syn);

    if par = '1' then
      -- odd number of flips: assume one, and fix it
      if p = 0 then
        r.corrected := '1';          -- the overall parity bit itself flipped
      elsif p <= 12 then
        fixed(p)    := not fixed(p); -- syndrome points straight at the bad bit
        r.corrected := '1';
      else
        r.uncorrectable := '1';      -- syndrome 13-15: impossible for 1 flip
      end if;
    elsif p /= 0 then
      r.uncorrectable := '1';        -- even parity but nonzero syndrome = 2 flips
    end if;

    for i in 0 to 7 loop
      r.data(i) := fixed(DATA_POS(i));
    end loop;
    return r;
  end function;

end package body;
