-- tb_mem_tester.vhd
-- Runs the tester in all three modes and checks the counters.
-- Expected: 16 injections per pattern x 6 patterns = 96.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_mem_tester is
end entity;

architecture sim of tb_mem_tester is
  constant CLK_PERIOD : time := 10 ns;

  signal clk   : std_logic := '0';
  signal rst   : std_logic := '1';
  signal start : std_logic := '0';
  signal inj_s : std_logic := '0';
  signal inj_d : std_logic := '0';
  signal busy, done : std_logic;
  signal inj_c, cor_c, unc_c, bad_c : unsigned(15 downto 0);
  signal cyc_c : unsigned(31 downto 0);
  signal finished : boolean := false;
begin

  clk_gen : process
  begin
    while not finished loop
      clk <= '0'; wait for CLK_PERIOD / 2;
      clk <= '1'; wait for CLK_PERIOD / 2;
    end loop;
    wait;
  end process;

  dut : entity work.mem_tester
    port map (clk => clk, rst => rst, start => start,
              inj_single => inj_s, inj_double => inj_d,
              busy => busy, done => done,
              inj_count => inj_c, cor_count => cor_c,
              unc_count => unc_c, bad_count => bad_c, cycles => cyc_c);

  stim : process
    type int_arr is array (0 to 2) of integer;
    type name_arr is array (0 to 2) of string(1 to 6);
    constant S_IN    : std_logic_vector(0 to 2) := "010";
    constant D_IN    : std_logic_vector(0 to 2) := "001";
    constant EXP_INJ : int_arr := (0, 96, 96);
    constant EXP_COR : int_arr := (0, 96, 0);
    constant EXP_UNC : int_arr := (0, 0, 96);
    constant NAMES   : name_arr := ("none  ", "1-bit ", "2-bit ");
    variable errors  : integer := 0;
  begin
    wait for 100 ns;
    wait until rising_edge(clk);
    rst <= '0';

    for t in 0 to 2 loop
      wait until rising_edge(clk);
      inj_s <= S_IN(t);
      inj_d <= D_IN(t);
      start <= '1';
      wait until rising_edge(clk);
      start <= '0';
      wait until rising_edge(clk) and done = '1';

      report "Mode " & NAMES(t)
             & " INJ=" & integer'image(to_integer(inj_c))
             & " COR=" & integer'image(to_integer(cor_c))
             & " UNC=" & integer'image(to_integer(unc_c))
             & " BAD=" & integer'image(to_integer(bad_c))
             & " CYC=" & integer'image(to_integer(cyc_c));

      if to_integer(inj_c) /= EXP_INJ(t) or to_integer(cor_c) /= EXP_COR(t)
         or to_integer(unc_c) /= EXP_UNC(t) or bad_c /= 0 then
        errors := errors + 1;
        report "Mode " & NAMES(t) & " counters wrong" severity error;
      end if;
    end loop;

    if errors = 0 then
      report "*** MEM_TESTER PASSED: all 3 modes correct ***";
    else
      report "*** MEM_TESTER FAILED ***" severity error;
    end if;
    finished <= true;
    wait;
  end process;

end architecture;
