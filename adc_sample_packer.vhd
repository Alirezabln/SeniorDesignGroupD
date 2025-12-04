library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity adc_sample_packer is
  port (
    clk_div   : in  std_logic;                -- ADC/controller clock
    rst_n     : in  std_logic;                -- active-low reset
    data1     : in  std_logic_vector(11 downto 0);
    data2     : in  std_logic_vector(11 downto 0);
    done_pulse: in  std_logic;                -- one-cycle pulse from AD1 controller
    wr_en     : out std_logic;                -- FIFO write enable (clk_div domain)
    wr_data   : out std_logic_vector(31 downto 0)  -- packed sample
  );
end adc_sample_packer;

architecture rtl of adc_sample_packer is
  signal wr_data_reg : std_logic_vector(31 downto 0) := (others => '0');
  signal wr_en_reg   : std_logic := '0';
  signal first_skip  : std_logic := '1';  -- flag to skip first sample
begin
  process(clk_div, rst_n)
  begin
    if rst_n = '0' then
      wr_en_reg   <= '0';
      wr_data_reg <= (others => '0');
      first_skip  <= '1';
    elsif rising_edge(clk_div) then
      -- default
      wr_en_reg <= '0';
      -- on DONE, capture and assert write strobe for one cycle
      if done_pulse = '1' then
        -- Pack: [31:16]=DATA2 (zero-extended), [15:0]=DATA1 (zero-extended)
        wr_data_reg <= (std_logic_vector(resize(unsigned(data2), 16)) &
                        std_logic_vector(resize(unsigned(data1), 16)));
        wr_en_reg   <= '1';
      end if;
    end if;
  end process;

  wr_en  <= wr_en_reg;
  wr_data<= wr_data_reg;
end rtl;