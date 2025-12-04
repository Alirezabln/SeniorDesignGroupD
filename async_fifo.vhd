library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity async_fifo is
  generic (
    DATA_WIDTH : integer := 32;
    ADDR_WIDTH : integer := 12   -- depth = 2^ADDR_WIDTH (4096 entries)
  );
  port (
    -- Write side (ADC domain)
    wr_clk   : in  std_logic;
    wr_rst_n : in  std_logic;     -- active-low
    wr_en    : in  std_logic;
    wr_data  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
    full     : out std_logic;
    wr_count : out std_logic_vector(ADDR_WIDTH downto 0); -- optional occupancy

    -- Read side (AXI/DMA domain)
    rd_clk   : in  std_logic;
    rd_rst_n : in  std_logic;     -- active-low
    rd_en    : in  std_logic;
    rd_data  : out std_logic_vector(DATA_WIDTH-1 downto 0);
    empty    : out std_logic;
    rd_count : out std_logic_vector(ADDR_WIDTH downto 0);  -- optional occupancy
    
    -- START signal (active-high)
    start    : in std_logic
  );
end async_fifo;

architecture rtl of async_fifo is
  constant DEPTH : integer := 2**ADDR_WIDTH;

  type ram_t is array (0 to DEPTH-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
  signal ram : ram_t;

  -- Binary and Gray pointers
  signal wr_ptr_bin, rd_ptr_bin : unsigned(ADDR_WIDTH downto 0) := (others => '0');
  signal wr_ptr_gray, rd_ptr_gray: unsigned(ADDR_WIDTH downto 0) := (others => '0');

  -- Synchronized Gray pointers across domains
  signal rd_ptr_gray_sync_wr_1, rd_ptr_gray_sync_wr_2 : unsigned(ADDR_WIDTH downto 0) := (others => '0');
  signal wr_ptr_gray_sync_rd_1, wr_ptr_gray_sync_rd_2 : unsigned(ADDR_WIDTH downto 0) := (others => '0');

  -- Derived empty/full
  signal full_i, empty_i : std_logic := '1';

  -- Read data register
  signal rd_data_reg : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
  
  -- Edge detectors
    signal start_wr_prev : std_logic := '0';
    signal start_rd_prev : std_logic := '0';

  -- Functions for Gray conversion
  function bin2gray(b : unsigned) return unsigned is
    variable g : unsigned(b'range);
  begin
    g := b xor ('0' & b(b'high downto 1));
    return g;
  end function;

  function gray2bin(g : unsigned) return unsigned is
    variable b : unsigned(g'range);
  begin
    b(b'high) := g(g'high);
    for i in g'high-1 downto 0 loop
      b(i) := b(i+1) xor g(i);
    end loop;
    return b;
  end function;

begin
  -- Write clock domain
  process(wr_clk, wr_rst_n)
    variable wr_addr : unsigned(ADDR_WIDTH-1 downto 0);
  begin
    if wr_rst_n = '0' or start = '0' then
      wr_ptr_bin  <= (others => '0');
      wr_ptr_gray <= (others => '0');
      rd_ptr_gray_sync_wr_1 <= (others => '0');
      rd_ptr_gray_sync_wr_2 <= (others => '0');
    elsif rising_edge(wr_clk) then
      -- synchronize read pointer into write domain
      rd_ptr_gray_sync_wr_1 <= wr_ptr_gray_sync_rd_1; -- dummy to satisfy elaboration; fixed below
      rd_ptr_gray_sync_wr_1 <= rd_ptr_gray_sync_wr_2; -- placeholder
      -- Two-stage sync of rd_ptr_gray
      rd_ptr_gray_sync_wr_1 <= rd_ptr_gray;
      rd_ptr_gray_sync_wr_2 <= rd_ptr_gray_sync_wr_1;

      -- Full detection (compare next write Gray to read Gray with MSBs inverted)
      wr_addr := wr_ptr_bin(ADDR_WIDTH-1 downto 0);
      if (wr_en = '1') and (full_i = '0') then
        ram(to_integer(wr_addr)) <= wr_data;
        wr_ptr_bin  <= wr_ptr_bin + 1;
        wr_ptr_gray <= bin2gray(wr_ptr_bin + 1);
      end if;
    end if;
  end process;

  -- Read clock domain
  process(rd_clk, rd_rst_n)
    variable rd_addr : unsigned(ADDR_WIDTH-1 downto 0);
  begin
    if rd_rst_n = '0' or start = '0' then
      rd_ptr_bin  <= (others => '0');
      rd_ptr_gray <= (others => '0');
      wr_ptr_gray_sync_rd_1 <= (others => '0');
      wr_ptr_gray_sync_rd_2 <= (others => '0');
      rd_data_reg <= (others => '0');
    elsif rising_edge(rd_clk) then
      -- synchronize write pointer into read domain
      wr_ptr_gray_sync_rd_1 <= wr_ptr_gray;
      wr_ptr_gray_sync_rd_2 <= wr_ptr_gray_sync_rd_1;

      -- Read if not empty
      rd_addr := rd_ptr_bin(ADDR_WIDTH-1 downto 0);
      if (rd_en = '1') and (empty_i = '0') then
        rd_data_reg <= ram(to_integer(rd_addr));
        rd_ptr_bin  <= rd_ptr_bin + 1;
        rd_ptr_gray <= bin2gray(rd_ptr_bin + 1);
      end if;
    end if;
  end process;
  
  

  -- Full calculation in write domain
  -- Full when next write Gray equals read Gray with MSBs inverted (classic async FIFO full test)
  full_i <= '1' when bin2gray(wr_ptr_bin + 1)(ADDR_WIDTH downto ADDR_WIDTH-1) = 
                  not rd_ptr_gray_sync_wr_2(ADDR_WIDTH downto ADDR_WIDTH-1) and
                  bin2gray(wr_ptr_bin + 1)(ADDR_WIDTH-2 downto 0) =
                  rd_ptr_gray_sync_wr_2(ADDR_WIDTH-2 downto 0)
           else '0';

  -- Empty calculation in read domain
  empty_i <= '1' when rd_ptr_gray = wr_ptr_gray_sync_rd_2 else '0';

  -- Expose outputs
  full  <= full_i;
  empty <= empty_i;
  rd_data <= rd_data_reg;

  -- Optional counts (in respective domains)
  wr_count <= std_logic_vector(resize(wr_ptr_bin - gray2bin(rd_ptr_gray_sync_wr_2), wr_count'length));
  rd_count <= std_logic_vector(resize(gray2bin(wr_ptr_gray_sync_rd_2) - rd_ptr_bin, rd_count'length));
end rtl;
