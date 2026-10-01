-- tb_secded.vhd
-- Exhaustive ECC check: all 256 data values, with
--   no error, every possible 1-bit error (13), every possible 2-bit error (78).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.secded_pkg.all;

entity tb_secded is
end entity;

architecture sim of tb_secded is
begin

  process
    variable d        : data_t;
    variable c, c1, c2 : code_t;
    variable r        : decode_t;
    variable errors   : integer := 0;
    variable checks   : integer := 0;
  begin
    for v in 0 to 255 loop
      d := std_logic_vector(to_unsigned(v, 8));
      c := secded_encode(d);

      -- clean codeword
      r := secded_decode(c);
      checks := checks + 1;
      if r.data /= d or r.corrected = '1' or r.uncorrectable = '1' then
        errors := errors + 1;
        report "Clean decode failed, data=" & integer'image(v) severity error;
      end if;

      for i in 0 to 12 loop
        -- single-bit error: must be corrected
        c1 := c;
        c1(i) := not c1(i);
        r := secded_decode(c1);
        checks := checks + 1;
        if r.data /= d or r.corrected /= '1' or r.uncorrectable = '1' then
          errors := errors + 1;
          report "1-bit fail, data=" & integer'image(v) & " bit=" & integer'image(i)
                 severity error;
        end if;

        -- double-bit error: must be detected
        for j in i + 1 to 12 loop
          c2 := c1;
          c2(j) := not c2(j);
          r := secded_decode(c2);
          checks := checks + 1;
          if r.uncorrectable /= '1' then
            errors := errors + 1;
            report "2-bit miss, data=" & integer'image(v) & " bits="
                   & integer'image(i) & "," & integer'image(j) severity error;
          end if;
        end loop;
      end loop;
    end loop;

    if errors = 0 then
      report "*** SECDED PASSED: " & integer'image(checks) & " cases ***";
    else
      report "*** SECDED FAILED: " & integer'image(errors) & " of "
             & integer'image(checks) & " ***" severity error;
    end if;
    wait;
  end process;

end architecture;
