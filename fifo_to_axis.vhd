library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fifo_to_axis_s2mm is
  generic (
    DATA_WIDTH  : integer := 32
  );
  port (
    -- AXI clock/reset
    axi_clk   : in  std_logic;
    axi_rst_n : in  std_logic;   -- active-low

    -- FIFO read side
    fifo_empty : in  std_logic;
    fifo_rd_en : out std_logic;
    fifo_rd_data : in std_logic_vector(DATA_WIDTH-1 downto 0);

    -- AXI-Stream S2MM
    m_axis_tdata  : out std_logic_vector(DATA_WIDTH-1 downto 0);
    m_axis_tvalid : out std_logic;
    m_axis_tready : in  std_logic;
    m_axis_tlast  : out std_logic;
    
    -- programmable frame length
    frame_length  : in  unsigned(11 downto 0)
  );
end fifo_to_axis_s2mm;

architecture rtl of fifo_to_axis_s2mm is
  signal tvalid_r : std_logic := '0';
  signal tlast_r  : std_logic := '0';
  signal tdata_r  : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
  signal word_cnt : unsigned(31 downto 0) := (others => '0');
  
      -- AXI-Lite interface signals (simplified)
    signal s_axi_awaddr  : std_logic_vector(3 downto 0);
    signal s_axi_awvalid : std_logic;
    signal s_axi_wdata   : std_logic_vector(31 downto 0);
    signal s_axi_wvalid  : std_logic;
    signal s_axi_bready  : std_logic;
    signal s_axi_araddr  : std_logic_vector(3 downto 0);
    signal s_axi_arvalid : std_logic;
    signal s_axi_rready  : std_logic;
    
    signal s_axi_awready : std_logic := '0';
    signal s_axi_wready  : std_logic := '0';
    signal s_axi_bvalid  : std_logic := '0';
    signal s_axi_arready : std_logic := '0';
    signal s_axi_rvalid  : std_logic := '0';
    signal s_axi_rdata   : std_logic_vector(31 downto 0) := (others => '0');
  
begin
  process(axi_clk, axi_rst_n)
  begin
    if axi_rst_n = '0' then
      tvalid_r <= '0';
      tlast_r  <= '0';
      tdata_r  <= (others => '0');
      word_cnt <= (others => '0');
      fifo_rd_en <= '0';
    elsif rising_edge(axi_clk) then
      -- Default
      fifo_rd_en <= '0';
      tlast_r    <= '0';

      -- Ready/valid handshake: when DMA ready and we have data
      if (m_axis_tready = '1') then
        if (fifo_empty = '0') then
          -- pull next word
          fifo_rd_en <= '1';
          tdata_r    <= fifo_rd_data;
          tvalid_r   <= '1';

          -- frame count and TLAST
        if word_cnt = frame_length - 1 then
            tlast_r  <= '1';
            word_cnt <= (others => '0');
        else
            word_cnt <= word_cnt + 1;
        end if;
        else
          -- no data available
          tvalid_r <= '0';
        end if;
      end if;
    end if;
  end process;

  m_axis_tdata  <= tdata_r;
  m_axis_tvalid <= tvalid_r;
  m_axis_tlast  <= tlast_r;
end rtl;
