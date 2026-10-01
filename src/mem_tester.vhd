-- mem_tester.vhd
-- Runs every test pattern over the whole RAM:
--   WRITE pass : encode expected data with SECDED, optionally corrupt it, store it
--   READ pass  : read back, decode, correct, compare against expected data
--
-- Fault injection (latched at start):
--   inj_single = '1' : flip 1 bit in every 64th word  -> ECC should correct all
--   inj_double = '1' : flip 2 bits in every 64th word -> ECC should detect all
-- The flipped bit position rotates with the address so every one of the
-- 13 codeword bits gets exercised.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.secded_pkg.all;
use work.tester_pkg.all;

entity mem_tester is
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;
    start      : in  std_logic;
    inj_single : in  std_logic;
    inj_double : in  std_logic;
    busy       : out std_logic;
    done       : out std_logic;              -- 1-cycle pulse when finished
    inj_count  : out unsigned(15 downto 0);  -- faults injected
    cor_count  : out unsigned(15 downto 0);  -- single-bit errors corrected
    unc_count  : out unsigned(15 downto 0);  -- double-bit errors detected
    bad_count  : out unsigned(15 downto 0);  -- wrong data with NO error flag
    cycles     : out unsigned(31 downto 0)   -- clock cycles the test took
  );
end entity;

architecture rtl of mem_tester is
  type state_t is (IDLE, WRITE, READ_ADDR, READ_CHECK);
  signal state : state_t := IDLE;

  constant LAST_ADDR : unsigned(ADDR_W - 1 downto 0) := (others => '1');

  signal pattern     : integer range 0 to NUM_PATTERNS - 1 := 0;
  signal addr        : unsigned(ADDR_W - 1 downto 0) := (others => '0');
  signal mode_single : std_logic := '0';
  signal mode_double : std_logic := '0';

  signal we          : std_logic;
  signal din, dout   : code_t;
  signal inject_here : std_logic;
  signal flip_mask   : code_t;
  signal dec         : decode_t;

  signal inj_c, cor_c, unc_c, bad_c : unsigned(15 downto 0) := (others => '0');
  signal cyc_c  : unsigned(31 downto 0) := (others => '0');
  signal done_r : std_logic := '0';
begin

  u_ram : entity work.bram_sp
    generic map (ADDR_W => ADDR_W, DATA_W => 13)
    port map (clk => clk, we => we, addr => addr, din => din, dout => dout);

  we <= '1' when state = WRITE else '0';

  -- inject into every 64th word (address low 6 bits all zero)
  inject_here <= '1' when addr(5 downto 0) = "000000"
                      and (mode_single = '1' or mode_double = '1') else '0';

  -- which codeword bit(s) to flip: rotates through all 13 positions
  flip_proc : process (addr, mode_double, inject_here)
    variable k : integer range 0 to 12;
    variable m : code_t;
  begin
    m := (others => '0');
    k := to_integer(addr(ADDR_W - 1 downto ADDR_W - 4)) mod 13;
    if inject_here = '1' then
      m(k) := '1';
      if mode_double = '1' then
        m((k + 1) mod 13) := '1';
      end if;
    end if;
    flip_mask <= m;
  end process;

  din <= secded_encode(expected_data(pattern, addr)) xor flip_mask;
  dec <= secded_decode(dout);

  process (clk)
  begin
    if rising_edge(clk) then
      done_r <= '0';
      if rst = '1' then
        state   <= IDLE;
        pattern <= 0;
        addr    <= (others => '0');
      else
        if state /= IDLE then
          cyc_c <= cyc_c + 1;
        end if;

        case state is

          when IDLE =>
            if start = '1' then
              mode_single <= inj_single;
              mode_double <= inj_double;
              inj_c   <= (others => '0');
              cor_c   <= (others => '0');
              unc_c   <= (others => '0');
              bad_c   <= (others => '0');
              cyc_c   <= (others => '0');
              pattern <= 0;
              addr    <= (others => '0');
              state   <= WRITE;
            end if;

          -- one word written per clock
          when WRITE =>
            if inject_here = '1' then
              inj_c <= inj_c + 1;
            end if;
            if addr = LAST_ADDR then
              addr  <= (others => '0');
              state <= READ_ADDR;
            else
              addr <= addr + 1;
            end if;

          -- address is on the RAM this cycle; data appears next cycle
          when READ_ADDR =>
            state <= READ_CHECK;

          when READ_CHECK =>
            if dec.uncorrectable = '1' then
              unc_c <= unc_c + 1;
            elsif dec.data /= expected_data(pattern, addr) then
              bad_c <= bad_c + 1;           -- silent corruption: the worst case
            elsif dec.corrected = '1' then
              cor_c <= cor_c + 1;
            end if;

            if addr = LAST_ADDR then
              addr <= (others => '0');
              if pattern = NUM_PATTERNS - 1 then
                state  <= IDLE;
                done_r <= '1';
              else
                pattern <= pattern + 1;
                state   <= WRITE;
              end if;
            else
              addr  <= addr + 1;
              state <= READ_ADDR;
            end if;

        end case;
      end if;
    end if;
  end process;

  busy      <= '0' when state = IDLE else '1';
  done      <= done_r;
  inj_count <= inj_c;
  cor_count <= cor_c;
  unc_count <= unc_c;
  bad_count <= bad_c;
  cycles    <= cyc_c;

end architecture;
