-- bram_sp.vhd
-- Single-port RAM written so Vivado infers a real block RAM.
-- Synchronous read: dout shows the word at 'addr' one clock after addr is set.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bram_sp is
  generic (
    ADDR_W : integer := 10;
    DATA_W : integer := 13
  );
  port (
    clk  : in  std_logic;
    we   : in  std_logic;
    addr : in  unsigned(ADDR_W - 1 downto 0);
    din  : in  std_logic_vector(DATA_W - 1 downto 0);
    dout : out std_logic_vector(DATA_W - 1 downto 0)
  );
end entity;

architecture rtl of bram_sp is
  type ram_t is array (0 to 2 ** ADDR_W - 1) of std_logic_vector(DATA_W - 1 downto 0);
  signal ram : ram_t := (others => (others => '0'));
begin

  process (clk)
  begin
    if rising_edge(clk) then
      if we = '1' then
        ram(to_integer(addr)) <= din;
      end if;
      dout <= ram(to_integer(addr));
    end if;
  end process;

end architecture;
