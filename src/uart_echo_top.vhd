-- uart_echo_top.vhd
-- Phase 1 top level: echoes every received byte back to the PC
-- and shows the last byte on LED[7:0].

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_echo_top is
  generic (
    CLKS_PER_BIT : integer := 868   -- 100 MHz / 115200 baud
  );
  port (
    CLK100MHZ    : in  std_logic;
    CPU_RESETN   : in  std_logic;                     -- red reset button, active low
    UART_TXD_IN  : in  std_logic;                     -- PC -> FPGA
    UART_RXD_OUT : out std_logic;                     -- FPGA -> PC
    LED          : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of uart_echo_top is
  signal rst       : std_logic;
  signal rx_data   : std_logic_vector(7 downto 0);
  signal rx_valid  : std_logic;
  signal tx_start  : std_logic := '0';
  signal tx_data   : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_busy   : std_logic;
  signal pending   : std_logic := '0';
  signal echo_byte : std_logic_vector(7 downto 0) := (others => '0');
  signal led_reg   : std_logic_vector(7 downto 0) := (others => '0');
begin

  rst <= not CPU_RESETN;
  LED <= led_reg;

  u_rx : entity work.uart_rx
    generic map (CLKS_PER_BIT => CLKS_PER_BIT)
    port map (
      clk      => CLK100MHZ,
      rst      => rst,
      rx       => UART_TXD_IN,
      data_out => rx_data,
      valid    => rx_valid
    );

  u_tx : entity work.uart_tx
    generic map (CLKS_PER_BIT => CLKS_PER_BIT)
    port map (
      clk     => CLK100MHZ,
      rst     => rst,
      start   => tx_start,
      data_in => tx_data,
      tx      => UART_RXD_OUT,
      busy    => tx_busy
    );

  -- One-byte buffer: the next byte can arrive while the previous echo
  -- is still finishing its stop bit, so we hold it until TX is free.
  process (CLK100MHZ)
  begin
    if rising_edge(CLK100MHZ) then
      tx_start <= '0';
      if rst = '1' then
        pending <= '0';
        led_reg <= (others => '0');
      else
        if pending = '1' and tx_busy = '0' and tx_start = '0' then
          tx_data  <= echo_byte;
          tx_start <= '1';
          pending  <= '0';
        end if;
        -- placed after the send logic so a new byte always wins
        if rx_valid = '1' then
          echo_byte <= rx_data;
          led_reg   <= rx_data;
          pending   <= '1';
        end if;
      end if;
    end if;
  end process;

end architecture;
