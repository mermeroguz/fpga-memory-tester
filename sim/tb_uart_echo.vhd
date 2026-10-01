-- tb_uart_echo.vhd
-- Self-checking testbench: plays the PC side, sends bytes back-to-back,
-- and verifies each one is echoed correctly. Run with "run all".

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_uart_echo is
end entity;

architecture sim of tb_uart_echo is
  constant CLK_PERIOD : time    := 10 ns;          -- 100 MHz
  constant CPB        : integer := 868;            -- 115200 baud
  constant BIT_TIME   : time    := CLK_PERIOD * CPB;

  type byte_array is array (natural range <>) of std_logic_vector(7 downto 0);
  constant TEST_BYTES : byte_array := (x"41", x"5A", x"00", x"FF", x"A5");

  signal clk     : std_logic := '0';
  signal resetn  : std_logic := '0';
  signal pc_tx   : std_logic := '1';   -- PC -> FPGA
  signal fpga_tx : std_logic;          -- FPGA -> PC
  signal leds    : std_logic_vector(7 downto 0);
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

  dut : entity work.uart_echo_top
    generic map (CLKS_PER_BIT => CPB)
    port map (
      CLK100MHZ    => clk,
      CPU_RESETN   => resetn,
      UART_TXD_IN  => pc_tx,
      UART_RXD_OUT => fpga_tx,
      LED          => leds
    );

  -- PC transmitter: sends all test bytes back-to-back
  sender : process
  begin
    resetn <= '0';
    wait for 100 ns;
    resetn <= '1';
    wait for 1 us;
    for n in TEST_BYTES'range loop
      pc_tx <= '0';                                -- start bit
      wait for BIT_TIME;
      for i in 0 to 7 loop
        pc_tx <= TEST_BYTES(n)(i);                 -- LSB first
        wait for BIT_TIME;
      end loop;
      pc_tx <= '1';                                -- stop bit
      wait for BIT_TIME;
    end loop;
    wait;
  end process;

  -- PC receiver: checks each echoed byte
  checker : process
    variable got    : std_logic_vector(7 downto 0);
    variable errors : integer := 0;
  begin
    for n in TEST_BYTES'range loop
      wait until fpga_tx = '0';                    -- start bit edge
      wait for BIT_TIME / 2;                       -- middle of start bit
      for i in 0 to 7 loop
        wait for BIT_TIME;
        got(i) := fpga_tx;
      end loop;
      wait for BIT_TIME;
      if fpga_tx /= '1' then
        report "Byte " & integer'image(n) & ": missing stop bit" severity error;
        errors := errors + 1;
      end if;
      if got /= TEST_BYTES(n) then
        report "Byte " & integer'image(n) & ": expected "
               & integer'image(to_integer(unsigned(TEST_BYTES(n))))
               & " got " & integer'image(to_integer(unsigned(got)))
               severity error;
        errors := errors + 1;
      else
        report "Byte " & integer'image(n) & " echoed OK ("
               & integer'image(to_integer(unsigned(got))) & ")";
      end if;
    end loop;

    if errors = 0 then
      report "*** TEST PASSED: all bytes echoed correctly ***";
    else
      report "*** TEST FAILED: " & integer'image(errors) & " error(s) ***" severity error;
    end if;
    done <= true;
    wait;
  end process;

end architecture;
