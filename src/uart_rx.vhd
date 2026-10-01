-- uart_rx.vhd
-- UART receiver: 8 data bits, no parity, 1 stop bit (8N1).
-- CLKS_PER_BIT = clock frequency / baud rate  (100 MHz / 115200 = 868)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_rx is
  generic (
    CLKS_PER_BIT : integer := 868
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    rx       : in  std_logic;                     -- serial line from PC
    data_out : out std_logic_vector(7 downto 0);  -- received byte
    valid    : out std_logic                      -- 1-cycle pulse when byte is ready
  );
end entity;

architecture rtl of uart_rx is
  type state_t is (IDLE, START, DATA, STOP);
  signal state   : state_t := IDLE;
  signal rx_sync : std_logic_vector(1 downto 0) := "11";  -- 2-flop synchronizer
  signal clk_cnt : integer range 0 to CLKS_PER_BIT - 1 := 0;
  signal bit_idx : integer range 0 to 7 := 0;
  signal shreg   : std_logic_vector(7 downto 0) := (others => '0');
begin

  process (clk)
  begin
    if rising_edge(clk) then
      -- rx comes from outside the FPGA's clock domain, so synchronize it
      rx_sync <= rx_sync(0) & rx;
      valid   <= '0';

      if rst = '1' then
        state   <= IDLE;
        clk_cnt <= 0;
        bit_idx <= 0;
      else
        case state is

          when IDLE =>
            clk_cnt <= 0;
            bit_idx <= 0;
            if rx_sync(1) = '0' then          -- falling edge = start bit
              state <= START;
            end if;

          when START =>
            -- wait half a bit, then confirm the line is still low
            -- (rejects glitches, and centers all later samples mid-bit)
            if clk_cnt = (CLKS_PER_BIT - 1) / 2 then
              clk_cnt <= 0;
              if rx_sync(1) = '0' then
                state <= DATA;
              else
                state <= IDLE;
              end if;
            else
              clk_cnt <= clk_cnt + 1;
            end if;

          when DATA =>
            if clk_cnt = CLKS_PER_BIT - 1 then
              clk_cnt        <= 0;
              shreg(bit_idx) <= rx_sync(1);   -- LSB first
              if bit_idx = 7 then
                bit_idx <= 0;
                state   <= STOP;
              else
                bit_idx <= bit_idx + 1;
              end if;
            else
              clk_cnt <= clk_cnt + 1;
            end if;

          when STOP =>
            if clk_cnt = CLKS_PER_BIT - 1 then
              clk_cnt <= 0;
              state   <= IDLE;
              if rx_sync(1) = '1' then        -- valid stop bit
                valid <= '1';
              end if;
            else
              clk_cnt <= clk_cnt + 1;
            end if;

        end case;
      end if;
    end if;
  end process;

  data_out <= shreg;

end architecture;
