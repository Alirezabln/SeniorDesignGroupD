-------------------------------------------------------------------------
--	AD1_controller.VHD
-------------------------------------------------------------------------
--	Original Author 	: Todd Harless
--  Modified By         : Alireza Bolourian
-------------------------------------------------------------------------
--	Description : This file is the VHDL code for a PMOD-AD1 controller.
-------------------------------------------------------------------------
--	Revision History:
--  07/11/2005 Created	        (Todd Harless)
--  08/09/2005 revision 0.1		(Todd Harless)
--  11/16/2025 changed the reset logic to active low  (Alireza Bolourian)
--  11/23/2025 changed libraries to standard numeric  (Alireza Bolourian)
--  11/23/2025 changed std_logic_vector type to unsgined (Alireza Bolourian)
--  11/23/2025 added reset clause in OUTPUT_DECODE (Alireza Bolourian)
--  11/23/2025 parameterized sys_clk and sclk (Alireza Bolourian)
--  11/23/2025 modified DONE signal (pluse instead of level) (Alireza Bolourian)
--  11/23/2025 added comments to each process (Alireza Bolourian)
-------------------------------------------------------------------------

library IEEE;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_1164.ALL;

-------------------------------------------------------------------------
--Title 		: AD1 controller entity
--
--	Inputs		: 3
--	Outputs		: 3
--
--	Description	: 	This is the AD1 controller entity. The input ports are 
--					  	a parameterized clock and an asynchronous 
--						reset button along with the data from the ADC7476 that 
--						is serially shifted in on each clock cycle. The outputs 
--						are the SCLK signal which clocks the PMOD-AD1 board at 
--						a given value and a chip select signal (CS) that latches the 
--						data into the PMOD-AD1 board as well as an 12-bit output 
--						vector labeled DATA_OUT which can be used by any 
--						external components.
--
--------------------------------------------------------------------------


entity AD1_controller is
      generic (
        SYS_CLK_FREQ : integer := 125_000_000;   -- system clock frequency in Hz
        ADC_CLK_FREQ : integer := 20_000_000    -- desired ADC clock frequency in Hz
      );
	  Port	(	
     --General usage
	   CLK           : in std_logic;	-- System Clock      
	   RST		     : in std_logic;
	 
	 --Pmod interface signals
       SDATA1        : in std_logic;
	   SDATA2		 : in std_logic;
	   SCLK	         : out std_logic;
	   CS            : out std_logic;
		
	--User interface signals
	   DATA1         : out std_logic_vector(11 downto 0);
	   DATA2         : out std_logic_vector(11 downto 0);
	   START	     : in std_logic; 
       DONE          : out std_logic;
       clk_adc       : out std_logic
     		 
				
			);
end AD1_controller;

architecture AD1 of AD1_controller is

      constant DIVISOR : integer := SYS_CLK_FREQ / (2 * ADC_CLK_FREQ);
      -- divide by 2 because we toggle the clock (high + low = full period)  
   
--------------------------------------------------------------------------------
--      Title 		   : 	 Local signal assignments
--
--	    Description	   :     The following signals will be used to drive the processes of 
--						     this VHDL file.
--
--		current_state  :	 This signal will be the pointer that will point at the
--							 current state of the Finite State Machine of the 
--							 controller.
--		next_state     :	 This signal will be the pointer that will point at the
--							 current state of the Finite State Machine of the 
--							 controller.
--		temp1          :	 This is a 16-bit vector that will store the 16-bits of data 
--						     that are serially shifted-in form the  first ADC7476 chip inside the
--						     PMOD-AD1 board.
--		temp2          :	 This is a 16-bit vector that will store the 16-bits of data 
--						     that are serially shifted-in form the second ADC7476 chip inside the
--						     PMOD-AD1 board.
--		dat1           :	 This is a 12-bit vector that will store the 12-bits of actual data 
--						     that are serially shifted-in form the  first ADC7476 chip inside the
--						     PMOD-AD1 board.
--		dat2           :	 This is a 12-bit vector that will store the 12-bits of actual data 
--						     that are serially shifted-in form the second ADC7476 chip inside the
--						     PMOD-AD1 board.
--		clk_div	       : 	 This will be the divided 12.5 MHz clock signal that will
--						     clock the PMOD-AD1 board
--		clk_counter	   :	 This counter will be used to create a divided clock signal.
--
--		shiftCounter   :	 This counter will be used to count the shifted data from the 
--						     ADC7476 chip inside the PMOD-AD1 board.
--		enShiftCounter :	 This signal will be used to  enable the counter for the shifted  
--						     data from the ADC7476 chip inside the PMOD-AD1 board.
--		enParallelLoad :	 This signal will be used to  enable the load in a register the shifted  
--						     data.
--------------------------------------------------------------------------------

type states is (Idle, ShiftIn, SyncData, DonePulse);  
		  signal current_state : states;
		  signal next_state    : states;
		  	  	 
		  signal temp1         : unsigned(15 downto 0) := (others => '0');
		  signal temp2         : unsigned(15 downto 0) := (others => '0'); 
          signal dat1          : unsigned(11 downto 0):=(others => '0');
		  signal dat2          : unsigned(11 downto 0):=(others => '0');        		  
		  signal shiftCounter  : unsigned(3 downto 0) := (others => '0'); 
		  signal enShiftCounter: std_logic;
		  signal enParallelLoad: std_logic;
		  signal clk_counter   : unsigned(31 downto 0) := (others => '0');
          signal clk_div       : std_logic := '0';

begin



--------------------------------------------------------------------------------
--      Title	    : 	clock divider process
--
--		Description	:	This is the process that will divide the generic clock 
--						down to a generic clock (MHz) to drive the ADC7476 chip. 
--------------------------------------------------------------------------------		
    clock_divide : process (CLK, RST)
    begin
      -- Asynchronous reset: when RST is asserted low, clear the counter and reset clk_div
      if RST = '0' then
        clk_counter <= (others => '0');  -- reset counter to all zeros
        clk_div     <= '0';              -- reset divided clock output
    
      -- Normal operation: on each rising edge of the system clock
      elsif rising_edge(CLK) then
        -- If counter has reached the terminal count (DIVISOR - 1)...
        if clk_counter = DIVISOR - 1 then
          clk_counter <= (others => '0');   -- reset counter back to zero
          clk_div     <= not clk_div;       -- toggle divided clock (creates square wave)
    
        -- Otherwise, just increment the counter
        else
          clk_counter <= clk_counter + 1;
        end if;
      end if;
    end process;
    
    -- Assign divided clock to SCLK only when shifting data
    SCLK <= clk_div when enShiftCounter = '1' else '1';
    clk_adc <= clk_div;

-----------------------------------------------------------------------------------
--
-- Title      :      counter
--
-- Description:      This is the process were the temporary registers will be loaded and 
--                   shifted. When the enParallelLoad signal is generated inside the state 
--                   the temp1 and temp2 registers will be loaded with the 8 bits of control
--			         concatenated with the 8 bits of data. When the enShiftCounter is 
--                   activated, the 16-bits of data inside the temporary registers will be 
--                   shifted. A 4-bit counter is used to keep shifting the data 
--					 inside temp1 and temp2 for 16 clock cycles.
--	
-----------------------------------------------------------------------------------	

    counter : process(clk_div, enParallelLoad, enShiftCounter)
    begin
      -- Trigger on rising edge of the divided ADC clock
      if rising_edge(clk_div) then
    
        -- Case 1: Shifting data in from ADCs
        if (enShiftCounter = '1') then
          -- Shift left by one bit and append the new serial input bit
          temp1 <= temp1(14 downto 0) & SDATA1;  -- shift in bit from ADC1
          temp2 <= temp2(14 downto 0) & SDATA2;  -- shift in bit from ADC2
    
          -- Increment the shift counter (tracks how many bits have been shifted in)
          shiftCounter <= shiftCounter + 1;
    
        -- Case 2: Parallel load of final data
        elsif (enParallelLoad = '1') then
          -- Reset shift counter for next conversion
          shiftCounter <= (others => '0');
    
          -- Capture the lower 12 bits of the shift registers as actual ADC data
          dat1 <= temp1(11 downto 0);  -- 12-bit result from ADC1
          dat2 <= temp2(11 downto 0);  -- 12-bit result from ADC2
        end if;
    
      end if;
    end process;

    -- Drive external outputs with the captured ADC data
    DATA1 <= std_logic_vector(dat1);
    DATA2 <= std_logic_vector(dat2);
---------------------------------------------------------------------------------
--
-- Title      :      Finite State Machine
--
-- Description:      This 3 processes represent the FSM that contains three states. The first 
--					 state is the Idle state in which a temporary registers are 
--					 assigned the updated value of the input "DATA1" and "DATA2". The next state 
--					 is the ShiftIn state where the 16-bits of 
--					 data from each of the ADCS7476 chips are left shifted in the temp1 and temp2 shift registers.
--					 The third 
--					 state SyncData drives the output signal CS high for
--					 1 clock period, and the second one in the Idle state telling the ADCS7476 to mark the end of the conversion.
-- Notes:		     The data will change on the lower edge of the clock signal. Their 
--					 is also an asynchronous reset that will reset all signals to their 
--					 original state.
--
-----------------------------------------------------------------------------------		
		
-----------------------------------------------------------------------------------
--
-- Title      : SYNC_PROC
--
-- Description: This is the process were the states are changed synchronously. At 
--              reset the current state becomes Idle state.
--	
-----------------------------------------------------------------------------------			
    SYNC_PROC: process (clk_div, rst)
    begin
      -- Trigger on rising edge of the divided ADC clock
      if rising_edge(clk_div) then
    
        -- Asynchronous reset: when RST is asserted low, force FSM into Idle state
        if (rst = '0') then
          current_state <= Idle;
    
        -- Normal operation: update current_state with next_state
        else
          current_state <= next_state;
        end if;
    
      end if;
    end process;
-----------------------------------------------------------------------------------
--
-- Title      : OUTPUT_DECODE
--
-- Description: This is the process were the output signals are generated
--              unsynchronously based on the state only (Moore State Machine).
    OUTPUT_DECODE: process (current_state)
    begin
      -- Defaults
      enShiftCounter <= '0';
      enParallelLoad <= '0';
      CS             <= '1';
      DONE           <= '0';
    
      case current_state is
        when Idle =>
          null;
    
        when ShiftIn =>
          enShiftCounter <= '1';
          CS             <= '0';
    
        when SyncData =>
          -- Load new data into dat1/dat2
          enParallelLoad <= '1';
          CS             <= '1';   -- release chip select
    
        when DonePulse =>
          -- One cycle later, assert DONE
          DONE <= '1';
    
        when others =>
          null;
      end case;
    end process;
----------------------------------------------------------------------------------
--
-- Title      : NEXT_STATE_DECODE
--
-- Description: This is the process were the next state logic is generated 
--              depending on the current state and the input signals.
--	
-----------------------------------------------------------------------------------	
    NEXT_STATE_DECODE: process (current_state, START, shiftCounter)
    begin
      next_state <= current_state;
    
      case current_state is
        when Idle =>
          if START = '1' then
            next_state <= ShiftIn;
          end if;
    
        when ShiftIn =>
          if shiftCounter = 15 then
            next_state <= SyncData;
          end if;
    
        when SyncData =>
          -- After loading data, go to DonePulse
          next_state <= DonePulse;
    
        when DonePulse =>
          -- Pulse DONE for one cycle, then return to Idle
          if START = '0' then
            next_state <= Idle;
          else
            next_state <= ShiftIn;  -- if continuous sampling
          end if;
    
        when others =>
          next_state <= Idle;
      end case;
    end process;

end AD1;