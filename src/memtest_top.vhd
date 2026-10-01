-- memtest_top.vhd
-- Final top level: FPGA memory tester with SECDED ECC and fault injection.
--
-- Controls:
--   UART 'T' (or press BTNC)  run the full test
--   SW0 = 1                   inject single-bit faults
--   SW1 = 1                   inject double-bit faults (overrides SW0)
--   any other key             print help
--
-- Outputs:
--   UART report line   RESULT=PASS MODE=S INJ=0060 COR=0060 UNC=0000 BAD=0000 CYC=........
--   7-seg              left 4 digits = corrected count, right 4 = uncorrectable count
--   LED0 = PASS, LED1 = FAIL, LED2 = test running

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tester_pkg.all;

entity memtest_top is
  generic (
    CLKS_PER_BIT  : integer := 868;   -- 100 MHz / 115200 baud
    DEBOUNCE_BITS : integer := 20     -- 2^20 cycles = ~10 ms button debounce
  );
  port (
    CLK100MHZ    : in  std_logic;
    CPU_RESETN   : in  std_logic;
    BTNC         : in  std_logic;
    SW           : in  std_logic_vector(1 downto 0);
    UART_TXD_IN  : in  std_logic;
    UART_RXD_OUT : out std_logic;
    LED          : out std_logic_vector(2 downto 0);
    SEG          : out std_logic_vector(6 downto 0);
    DP           : out std_logic;
    AN           : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of memtest_top is
  constant MSG_MAX : integer := 80;
  type msg_t is array (0 to MSG_MAX - 1) of std_logic_vector(7 downto 0);

  signal rst      : std_logic;
  signal rx_data  : std_logic_vector(7 downto 0);
  signal rx_valid : std_logic;
  signal tx_start : std_logic := '0';
  signal tx_data  : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_busy  : std_logic;

  signal sw_s0, sw_s1 : std_logic_vector(1 downto 0) := "00";
  signal btn_sync     : std_logic_vector(1 downto 0) := "00";
  signal btn_cnt      : unsigned(DEBOUNCE_BITS - 1 downto 0) := (others => '0');
  signal btn_stable   : std_logic := '0';
  signal btn_prev     : std_logic := '0';
  signal btn_press    : std_logic;

  signal t_start : std_logic := '0';
  signal t_busy  : std_logic;
  signal t_done  : std_logic;
  signal inj_c, cor_c, unc_c, bad_c : unsigned(15 downto 0);
  signal cyc_c   : unsigned(31 downto 0);

  type ctrl_t is (C_IDLE, C_TESTING, C_SEND, C_WAIT_BUSY, C_WAIT_DONE);
  signal ctrl     : ctrl_t := C_IDLE;
  signal msg      : msg_t := (others => (others => '0'));
  signal msg_len  : integer range 0 to MSG_MAX := 0;
  signal idx      : integer range 0 to MSG_MAX := 0;
  signal mode_r   : std_logic_vector(1 downto 0) := "00";
  signal pass_r   : std_logic := '0';
  signal fail_r   : std_logic := '0';
  signal disp_val : std_logic_vector(31 downto 0) := (others => '0');
begin

  rst <= not CPU_RESETN;

  ---------------------------------------------------------------------------
  -- Submodules
  ---------------------------------------------------------------------------
  u_rx : entity work.uart_rx
    generic map (CLKS_PER_BIT => CLKS_PER_BIT)
    port map (clk => CLK100MHZ, rst => rst, rx => UART_TXD_IN,
              data_out => rx_data, valid => rx_valid);

  u_tx : entity work.uart_tx
    generic map (CLKS_PER_BIT => CLKS_PER_BIT)
    port map (clk => CLK100MHZ, rst => rst, start => tx_start,
              data_in => tx_data, tx => UART_RXD_OUT, busy => tx_busy);

  u_tester : entity work.mem_tester
    port map (clk => CLK100MHZ, rst => rst, start => t_start,
              inj_single => mode_r(0), inj_double => mode_r(1),
              busy => t_busy, done => t_done,
              inj_count => inj_c, cor_count => cor_c,
              unc_count => unc_c, bad_count => bad_c, cycles => cyc_c);

  u_seg : entity work.seg7_mux
    port map (clk => CLK100MHZ, value => disp_val, seg => SEG, an => AN);

  DP  <= '1';   -- decimal points off
  LED <= t_busy & fail_r & pass_r;

  ---------------------------------------------------------------------------
  -- Switch sync + button debounce (buttons bounce for a few ms when pressed)
  ---------------------------------------------------------------------------
  process (CLK100MHZ)
  begin
    if rising_edge(CLK100MHZ) then
      sw_s0    <= SW;
      sw_s1    <= sw_s0;
      btn_sync <= btn_sync(0) & BTNC;

      if btn_sync(1) = btn_stable then
        btn_cnt <= (others => '0');
      elsif btn_cnt = (btn_cnt'range => '1') then
        btn_stable <= btn_sync(1);        -- held long enough: accept new level
        btn_cnt    <= (others => '0');
      else
        btn_cnt <= btn_cnt + 1;
      end if;

      btn_prev <= btn_stable;
    end if;
  end process;

  btn_press <= btn_stable and not btn_prev;   -- one pulse per press

  ---------------------------------------------------------------------------
  -- Control: start tests, build report text, send it byte by byte
  ---------------------------------------------------------------------------
  ctrl_proc : process (CLK100MHZ)
    variable m  : msg_t;
    variable p  : integer;
    variable ok : boolean;

    procedure put_char(variable mm : inout msg_t; variable pp : inout integer;
                       c : in character) is
    begin
      mm(pp) := std_logic_vector(to_unsigned(character'pos(c), 8));
      pp := pp + 1;
    end procedure;

    procedure put_str(variable mm : inout msg_t; variable pp : inout integer;
                      s : in string) is
    begin
      for i in s'range loop
        put_char(mm, pp, s(i));
      end loop;
    end procedure;

    procedure put_hex(variable mm : inout msg_t; variable pp : inout integer;
                      v : in unsigned) is
      variable vv : unsigned(v'length - 1 downto 0);
    begin
      vv := v;
      for i in v'length / 4 - 1 downto 0 loop
        mm(pp) := hex_char(std_logic_vector(vv(i * 4 + 3 downto i * 4)));
        pp := pp + 1;
      end loop;
    end procedure;

  begin
    if rising_edge(CLK100MHZ) then
      tx_start <= '0';
      t_start  <= '0';

      if rst = '1' then
        ctrl   <= C_IDLE;
        idx    <= 0;
        pass_r <= '0';
        fail_r <= '0';
      else
        case ctrl is

          when C_IDLE =>
            if (rx_valid = '1' and (rx_data = x"54" or rx_data = x"74"))  -- 'T' / 't'
               or btn_press = '1' then
              mode_r  <= sw_s1;
              t_start <= '1';
              ctrl    <= C_TESTING;
            elsif rx_valid = '1' and rx_data /= x"0D" and rx_data /= x"0A" then
              m := (others => (others => '0'));
              p := 0;
              put_char(m, p, CR); put_char(m, p, LF);
              put_str(m, p, "Press T (or BTNC) to run test. SW0=1-bit, SW1=2-bit inject");
              put_char(m, p, CR); put_char(m, p, LF);
              msg     <= m;
              msg_len <= p;
              idx     <= 0;
              ctrl    <= C_SEND;
            end if;

          when C_TESTING =>
            if t_done = '1' then
              -- PASS means the ECC behaved exactly as expected for the mode
              ok := bad_c = 0;
              case mode_r is
                when "00"   => ok := ok and cor_c = 0 and unc_c = 0;
                when "01"   => ok := ok and cor_c = inj_c and unc_c = 0;
                when others => ok := ok and unc_c = inj_c and cor_c = 0;
              end case;

              if ok then
                pass_r <= '1'; fail_r <= '0';
              else
                pass_r <= '0'; fail_r <= '1';
              end if;
              disp_val <= std_logic_vector(cor_c & unc_c);

              m := (others => (others => '0'));
              p := 0;
              put_char(m, p, CR); put_char(m, p, LF);
              put_str(m, p, "RESULT=");
              if ok then put_str(m, p, "PASS"); else put_str(m, p, "FAIL"); end if;
              put_str(m, p, " MODE=");
              case mode_r is
                when "00"   => put_char(m, p, 'N');
                when "01"   => put_char(m, p, 'S');
                when others => put_char(m, p, 'D');
              end case;
              put_str(m, p, " INJ="); put_hex(m, p, inj_c);
              put_str(m, p, " COR="); put_hex(m, p, cor_c);
              put_str(m, p, " UNC="); put_hex(m, p, unc_c);
              put_str(m, p, " BAD="); put_hex(m, p, bad_c);
              put_str(m, p, " CYC="); put_hex(m, p, cyc_c);
              put_char(m, p, CR); put_char(m, p, LF);
              msg     <= m;
              msg_len <= p;
              idx     <= 0;
              ctrl    <= C_SEND;
            end if;

          when C_SEND =>
            tx_data  <= msg(idx);
            tx_start <= '1';
            ctrl     <= C_WAIT_BUSY;

          when C_WAIT_BUSY =>                  -- wait for TX to accept the byte
            if tx_busy = '1' then
              ctrl <= C_WAIT_DONE;
            end if;

          when C_WAIT_DONE =>                  -- wait for TX to finish it
            if tx_busy = '0' then
              if idx = msg_len - 1 then
                idx  <= 0;
                ctrl <= C_IDLE;
              else
                idx  <= idx + 1;
                ctrl <= C_SEND;
              end if;
            end if;

        end case;
      end if;
    end if;
  end process;

end architecture;
