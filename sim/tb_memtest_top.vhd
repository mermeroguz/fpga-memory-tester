-- tb_memtest_top.vhd
-- End-to-end: acts as the PC, sends 'T' over UART with SW0=1 (1-bit injection),
-- reads the report line back and checks it says RESULT=PASS.
-- Simulates ~7 ms of time, so give it a minute. Use "run all".

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_memtest_top is
end entity;

architecture sim of tb_memtest_top is
  constant CLK_PERIOD : time    := 10 ns;
  constant CPB        : integer := 868;
  constant BIT_TIME   : time    := CLK_PERIOD * CPB;

  signal clk     : std_logic := '0';
  signal resetn  : std_logic := '0';
  signal pc_tx   : std_logic := '1';
  signal fpga_tx : std_logic;
  signal sw      : std_logic_vector(1 downto 0) := "01";
  signal led     : std_logic_vector(2 downto 0);
  signal seg     : std_logic_vector(6 downto 0);
  signal dp      : std_logic;
  signal an      : std_logic_vector(7 downto 0);
  signal done    : boolean := false;
begin

  clk_gen : process
  begin
    while not done loop
      clk <= '0'; wait for CLK_PERIOD / 2;
      clk <= '1'; wait for CLK_PERIOD / 2;
    end loop;
    wait;
  end process;

  dut : entity work.memtest_top
    generic map (CLKS_PER_BIT => CPB, DEBOUNCE_BITS => 4)
    port map (CLK100MHZ => clk, CPU_RESETN => resetn, BTNC => '0', SW => sw,
              UART_TXD_IN => pc_tx, UART_RXD_OUT => fpga_tx,
              LED => led, SEG => seg, DP => dp, AN => an);

  sender : process
    constant CMD : std_logic_vector(7 downto 0) := x"54";   -- 'T'
  begin
    wait for 100 ns;
    resetn <= '1';
    wait for 1 us;
    pc_tx <= '0';
    wait for BIT_TIME;
    for i in 0 to 7 loop
      pc_tx <= CMD(i);
      wait for BIT_TIME;
    end loop;
    pc_tx <= '1';
    wait;
  end process;

  receiver : process
    variable b    : std_logic_vector(7 downto 0);
    variable ch   : character;
    variable line_buf : string(1 to 100);
    variable len  : integer := 0;
  begin
    loop
      wait until fpga_tx = '0';
      wait for BIT_TIME / 2;
      for i in 0 to 7 loop
        wait for BIT_TIME;
        b(i) := fpga_tx;
      end loop;
      wait for BIT_TIME;
      ch := character'val(to_integer(unsigned(b)));

      if ch = LF then
        if len > 0 then
          report "UART: " & line_buf(1 to len);
          if len >= 11 and line_buf(1 to 7) = "RESULT=" then
            if line_buf(1 to 11) = "RESULT=PASS" then
              report "*** TOP-LEVEL PASSED ***";
            else
              report "*** TOP-LEVEL FAILED ***" severity error;
            end if;
            if led(0) /= '1' then
              report "PASS LED not lit" severity error;
            end if;
            done <= true;
            wait;
          end if;
        end if;
        len := 0;
      elsif ch /= CR and len < 100 then
        len := len + 1;
        line_buf(len) := ch;
      end if;
    end loop;
  end process;

end architecture;
