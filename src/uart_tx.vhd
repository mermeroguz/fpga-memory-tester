-- uart_tx.vhd
-- UART transmitter: 8N1. Pulse 'start' for one cycle while 'busy' = '0'.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is
  generic (
    CLKS_PER_BIT : integer := 868
  );
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;
    start   : in  std_logic;
    data_in : in  std_logic_vector(7 downto 0);
    tx      : out std_logic;   -- serial line to PC
    busy    : out std_logic
  );
end entity;

architecture rtl of uart_tx is
  type state_t is (IDLE, START_BIT, DATA, STOP_BIT);
  signal state   : state_t := IDLE;
  signal clk_cnt : integer range 0 to CLKS_PER_BIT - 1 := 0;
  signal bit_idx : integer range 0 to 7 := 0;
  signal shreg   : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_r    : std_logic := '1';   -- line idles high
begin

  tx   <= tx_r;
  busy <= '0' when state = IDLE else '1';

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state   <= IDLE;
        tx_r    <= '1';
        clk_cnt <= 0;
        bit_idx <= 0;
      else
        case state is

          when IDLE =>
            tx_r    <= '1';
            clk_cnt <= 0;
            bit_idx <= 0;
            if start = '1' then
              shreg <= data_in;               -- latch byte
              state <= START_BIT;
            end if;

          when START_BIT =>
            tx_r <= '0';
            if clk_cnt = CLKS_PER_BIT - 1 then
              clk_cnt <= 0;
              state   <= DATA;
            else
              clk_cnt <= clk_cnt + 1;
            end if;

          when DATA =>
            tx_r <= shreg(bit_idx);           -- LSB first
            if clk_cnt = CLKS_PER_BIT - 1 then
              clk_cnt <= 0;
              if bit_idx = 7 then
                bit_idx <= 0;
                state   <= STOP_BIT;
              else
                bit_idx <= bit_idx + 1;
              end if;
            else
              clk_cnt <= clk_cnt + 1;
            end if;

          when STOP_BIT =>
            tx_r <= '1';
            if clk_cnt = CLKS_PER_BIT - 1 then
              clk_cnt <= 0;
              state   <= IDLE;
            else
              clk_cnt <= clk_cnt + 1;
            end if;

        end case;
      end if;
    end if;
  end process;

end architecture;
