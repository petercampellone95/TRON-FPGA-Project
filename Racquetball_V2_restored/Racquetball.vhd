library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Racquetball is
   port( CLOCK_50 : in std_logic;
         SW : in std_logic_vector(9 downto 0);
         KEY : in std_logic_vector(3 downto 0);
         HEX0, HEX1, HEX2, HEX3, HEX4, HEX5: out std_logic_vector(6 DOWNTO 0);
         GPIO_1: out std_logic_vector(31 downto 0);
         MTL_TOUCH_INT_n : in std_logic;
         MTL_TOUCH_I2C_SCL : out std_logic;
         MTL_TOUCH_I2C_SDA : inout std_logic
         );
end entity;

architecture DE1_SoC_MTL2 of Racquetball is
   alias clock : std_logic is Clock_50;
   alias reset : std_logic is KEY(0);
   
   constant background : std_logic_vector(2 downto 0) := "000";
   constant bcolor : std_logic_vector(2 downto 0) := "001"; --Player1
   constant pcolor : std_logic_vector(2 downto 0) := "010"; --Player2
   constant border : std_logic_vector(2 downto 0) := "011"; 
   constant lives_sprite : std_logic_vector(2 downto 0) := "100";
   constant game_over_sprite: std_logic_vector(2 downto 0) := "101";
	
   constant speed_on : std_logic_vector(2 downto 0) := "110";
   constant speed_off : std_logic_vector(2 downto 0) := "111";
   
   constant screen_width:  integer := 50;
   constant screen_height: integer := 30;
   
   signal mem_in, mem_out, vdata: std_logic_vector(2 downto 0);
   signal mem_adr: std_logic_vector(10 downto 0);
   signal mem_wr: std_logic;
   signal slow_clock: std_logic;
   signal x, ballx, old_x : unsigned (5 downto 0);
   signal y, bally, old_y : unsigned (4 downto 0);
   signal go : Boolean;
   signal px : unsigned (5 downto 0);
   constant py : unsigned(4 downto 0) := to_unsigned(20, 5);
   signal ulv, urv, dlv, drv: unsigned(2 downto 0);

   signal op_num : integer range 0 to 2;
   type display is array (0 to 2) of std_logic_vector(15 downto 0);
   constant OP: display :=
            (x"5102", -- "StOP"
             x"304C", -- "gO=L"
             x"3046"  -- "gO=r"
             );

   type state is (clean0, clean1, clean2, clean3, sync1, sync2,
               perase1, perase2, pupdate, pdraw1, pdraw2, update1, 
               update2, update3, update4, update5, update6, update7, 
               update8, update9, update10, update11, erase1, erase2,
               bupdate, draw1, draw2,restart,ws0,ws1,ws2,ws3, move0, move1);
   

   signal SV : state;
      
   type direction is (ul, ur, dr, dl);
   signal dir: direction;

   type pdirection is (pleft, pright);
   signal pdir: pdirection;

   signal VGA_R, VGA_G, VGA_B : std_logic_vector(7 downto 0);
   alias  VGA_HS : std_logic is GPIO_1(30); --HSD
   alias  VGA_VS : std_logic is GPIO_1(31); --VSD
   alias  DCLK : std_logic is GPIO_1(1);  --pixel clock = 33.3MHz

   TYPE Touch_state IS (wait_for_ready, get_code, examine);
   SIGNAL TS : Touch_state;   
	
	TYPE Touch_gesture IS(wait_for_ready2, examine2);
	SIGNAL TG : Touch_gesture;
	
   signal gesture : std_logic_vector(7 downto 0);
   signal ready: std_logic;
   
   signal speed, old_speed: unsigned(3 downto 0);
   signal queue: std_logic_vector(1 downto 0);
   
   Signal X1 : std_logic_vector(9 downto 0);
   Signal Y1 : std_logic_vector(8 downto 0);
   Signal TX : unsigned(9 downto 0);
   Signal TY : unsigned(8 downto 0);
      
   
   component i2c_touch_config is port(
      iCLK : in std_logic;
      iRSTN : in std_logic;
      oREADY : out std_logic;
      INT_n : in std_logic;
      
      oREG_X1 : out std_logic_vector(9 downto 0);
      oREG_Y1 : out std_logic_vector(8 downto 0);
      oREG_X2 : out std_logic_vector(9 downto 0);
      oREG_Y2 : out std_logic_vector(8 downto 0);
      oREG_X3 : out std_logic_vector(9 downto 0);
      oREG_Y3 : out std_logic_vector(8 downto 0);
      oREG_X4 : out std_logic_vector(9 downto 0);        
      oREG_Y4 : out std_logic_vector(8 downto 0);
      oREG_X5 : out std_logic_vector(9 downto 0);
      oREG_Y5 : out std_logic_vector(8 downto 0);
      oREG_GESTURE : out std_logic_vector(7 downto 0);
      oREG_TOUCH_COUNT : out std_logic_vector(3 downto 0);
      I2C_SDAT : inout std_logic;
      I2C_SCLK : out std_logic
   ); end component i2c_touch_config;
   

begin
   GPIO_1(10 downto 3) <= VGA_R;
   GPIO_1(21) <= VGA_G(7);
   GPIO_1(19 downto 18) <= VGA_G(6 downto 5);
   GPIO_1(15 downto 11) <= VGA_G(4 downto 0);
   GPIO_1(28 downto 22) <= VGA_B(7 downto 1);
   GPIO_1(20) <= VGA_B(0);
   
  vga_interface : entity work.vga_sprite port map(
      clock => clock,   
      reset => not reset,  
      mem_adr => mem_adr,
      mem_out => mem_out,
      mem_in => mem_in,
      mem_wr => mem_wr,   
      vga_hs => vga_hs,
      vga_vs => vga_vs,
		pclock => DCLK,
      r => vga_r,
      g => vga_g,
      b => vga_b
   );
   mem_adr <= std_logic_vector(y) & std_logic_vector(x);

   Terasic_Touch_IP: i2c_touch_config port map(
      iclk => clock_50,
      iRSTN => key(0),
      int_n => MTL_TOUCH_INT_n,
      oready => ready,
      oREG_X1 => X1,
      oREG_Y1 => Y1,
      oreg_gesture => gesture,
      i2c_sclk => MTL_TOUCH_I2C_SCL,
      i2c_sdat => MTL_TOUCH_I2C_SDA
   );

   --dsp0: entity work.sevenseg port map (OP(op_num)(3 downto 0), HEX0);
   --dsp1: entity work.sevenseg port map (OP(op_num)(7 downto 4), HEX1);
   --dsp2: entity work.sevenseg port map (OP(op_num)(11 downto 8), HEX2);
   --dsp3: entity work.sevenseg port map (OP(op_num)(15 downto 12), HEX3);
   
	HEX0 <= "1111111";
   HEX1 <= "1111111";
	HEX2 <= "1111111";
   HEX3 <= "1111111";
	HEX4 <= "1111111";
   HEX5 <= "1111111";
   ------------------------------------------------------
   Touch_Sensor_Interface: process(CLOCK, reset)
   begin
      if(reset = '0') then 
         speed <= x"1";
         TS <= wait_for_ready;
      
		elsif(clock'event AND clock = '1') then
         CASE TS IS
            WHEN wait_for_ready =>
               if(ready='1') then
                  TS <= get_code;
               end if;
					
            WHEN get_code =>
               TX <= unsigned(X1);
               TY <= unsigned(Y1);
               TS <= examine;
              
            WHEN examine => --Done
               if(TX >= 16 and TX <= 23 and TY>=80 and TY<=87) then
						speed <= x"8";
					elsif(TX >= 16 and TX <= 23 and TY>=96 and TY<=103) then 
						speed <= x"4";
					elsif(TX >= 16 and TX <= 23 and TY>=112 and TY<=119) then
						speed <= x"2";
					elsif(TX >= 16 and TX <= 23 and TY>=128 and TY<=135) then
						speed <= x"1";
               end if;
               TS <= wait_for_ready;
               
            WHEN OTHERS =>
               TS <= wait_for_ready;
         END CASE;
      end if;     
   end process;
	
	Touch_gesture_handler: process(CLOCK, reset)
   begin
		if(reset = '0') then	
			go <= false;		--paddle not moving
			pdir <= pleft;		--paddle direction = left
			OP_num <= 0;		
			TG <= wait_for_ready2;
			
		elsif(clock'event AND clock = '1') then
			CASE TG IS
				WHEN wait_for_ready2 =>
					if(ready='1') then
						TG <= examine2;
					end if;
				WHEN examine2 =>	
					if(gesture = x"10") then	--Move Up
						go <= true;
						if(pdir=pleft) then OP_num <= 1;
							else OP_num <= 2;
						end if;
					elsif(gesture = x"18") then	--Move Down
						go <= false;
						OP_num <= 0;
					elsif(gesture = x"14") then	--Move Left
						go <= true;
						pdir <= pleft;
						OP_num <= 1;
					elsif(gesture = x"1C") then	--Move Right
						go <= true;
						pdir <= pright;
						OP_num <= 2;					
					end if;
				WHEN OTHERS =>
					TG <= wait_for_ready2;
			END CASE;
		end if;		
   end process;
	
   ------------------------------------------------------
   display_clock: process(clock, reset) --Done
      variable loopcount : integer range 0 to 200000;
      variable switchcount : integer range 0 to 15;
   begin
      if(reset = '0') then 
         loopcount := 0;
         switchcount := 0;
         slow_clock <= '0';
      elsif(clock'event AND clock = '1') then
         if(loopcount >= 199999) then
            loopcount := 0;
            if(switchcount >= speed) then
               slow_clock <= not slow_clock;
               switchcount := 0;
            else
               switchcount := switchcount + 1;
            end if;
         else
            loopcount := loopcount + 1;
         end if;
      end if;     
      end process;
      ----------------------------------------------------------
      main: process(clock, reset)
      variable lives : integer range 0 to 3;
      variable count : integer range 0 to 7;
      begin
      
      if(reset = '0') then       
         mem_wr <= '0';    ------------------------------
         x <= "000000";   --initialization Video RAM
         y <= "00000"; --address: x=0 and y=0
              ------------------------------
         dir <= dr;
         BALLx <= "000101"; -- put ball's position
         BALLy <= "00101";  -- at {5, 5}    
         px <= to_unsigned(30, 6);  
         lives := 3;
			SV <= clean0;
      
		elsif(clock'event AND clock = '1') then
         case SV is
            when restart =>
               if(gesture = x"10") then
							lives:= lives - 1;
							x <= "000000";   
							y <= "00000"; 
							mem_wr <= '1';    
							dir <= dr;
							BALLx <= "000101"; -- put ball's position
							BALLy <= "00101";  -- at {5, 5}    
							px <= to_unsigned(30, 6);
							old_speed <= x"0";  
							SV <= clean0;
						else
							SV <= restart;
						end if;
               
            when clean0 => 
               mem_wr <= '1';    
               if(y = py and (x >= PX and x <= PX+4)) then
                  mem_in <= pcolor; --Works
               elsif(lives = 3 and (y = 0 and (x = 7 or x = 9 or x = 11))) then
                  mem_in <= lives_sprite; --Works
               elsif(lives = 2 and (y = 0 and (x = 9 or x = 11))) then
                  mem_in <= lives_sprite; --Works
               elsif(lives = 1 and (y = 0 and x = 11)) then
                  mem_in <= lives_sprite; --Works
               elsif((x = 3 and (y >= 1 and y <= 29)) or (x = 46 and (y >= 1 and y <= 29)) or (y = 1 and (x >= 3 and x <= 46)) or (y = 29 and (x >= 3 and x <= 46))) then
                  mem_in <= border;    --border color
               elsif(lives = 0 and (x = 30 and (x = 15 or x = 17 or x = 20))) then
						mem_in <= game_over_sprite;
						lives:= lives - 1;
						--SV <= restart;
					else
                  mem_in <= background;   
               end if;
               SV <= clean1;
               
            when clean1 => --Done
               x <= x+1;
               SV <= clean2;
            
				when clean2 => --Done
               mem_wr <= '0';    -- disable the write enable
               if(x> screen_width - 1) then 
                  x<= "000000";
                  y <= y+1;
                  SV <= clean3;
               else
                  SV <= clean0;
               end if;
               
            when clean3 => --Done
               if(y > screen_height - 1) then
                  SV <= move0;
               else
                  SV <= clean0;
               end if;
               
          when move0 =>
             queue <= queue(0) & slow_clock;
             SV <= move1;
          when move1 =>
             if (speed /= old_speed) then
                old_speed <= speed;
                SV <= ws0;
             elsif(queue = "01") then
                SV <= sync1;               --update speed button sprites    
             else
                SV <= move0;
             end if;
   
   --------------------------------------------------
            when ws0 =>
               count := 0;
               old_x <= x;
               old_y <= y;
               SV <= ws1;
            when ws1 => --Drawing/Updating speed buttons
               case count is
                  when 0 =>
                     X <= to_unsigned(1, 6);
                     Y <= to_unsigned(10, 5);
                     if(speed = x"8") then
                        mem_in <= "110";
                     else
                        mem_in <= "111";
                     end if;
                  when 1 =>
                     X <= to_unsigned(1, 6);
                     Y <= to_unsigned(12, 5);
                     if(speed = x"4") then
                        mem_in <= "110";
                     else
                        mem_in <= "111";
                     end if;
                  when 2 =>
                     X <= to_unsigned(1, 6);
                     Y <= to_unsigned(14, 5);
                     if(speed = x"2") then
                        mem_in <= "110";
                     else
                        mem_in <= "111";
                     end if;
                  when 3 =>
                     X <= to_unsigned(1, 6);
                     Y <= to_unsigned(16, 5);
                     if(speed = x"1") then
                        mem_in <= "110";
                     else
                        mem_in <= "111";
                     end if;
						
				
						when 4 => --AI button 1
                     X <= to_unsigned(48, 6);
                     Y <= to_unsigned(10, 5);
                     if(speed = x"8") then
                        mem_in <= "110";
                     else
                        mem_in <= "111";
                     end if;
                  
						when 5 => --AI button 2
                     X <= to_unsigned(48, 6);
                     Y <= to_unsigned(12, 5);
                     if(speed = x"4") then
                        mem_in <= "110";
                     else
                        mem_in <= "111";
                     end if;
                  
						when 6 => --AI button 3
                     X <= to_unsigned(48, 6);
                     Y <= to_unsigned(14, 5);
                     if(speed = x"2") then
                        mem_in <= "110";
                     else
                        mem_in <= "111";
                     end if;
                  
						when 7 => --AI button 4
                     X <= to_unsigned(48, 6);
                     Y <= to_unsigned(16, 5);
                     if(speed = x"1") then
                        mem_in <= "110";
                     else
                        mem_in <= "111";
                     end if;	
                  when others =>
                     null;
               end case;
               mem_wr <= '1'; 
               SV <= ws2;  
            
				when ws2 =>
               count := count + 1;
               SV <= ws3;
            when ws3 =>
               mem_wr <= '0'; 
               if(count <= 7) then 
                  SV <= ws1;
               else
                  X <= old_x;
                  Y <= old_y;
                  SV <= move0;
               end if;
            --------------------------------------------------
            
            when sync1 =>        --Sync1 and sync2 wait
               mem_wr <= '0';    --for the rising edge
               if(slow_clock = '0') then  --of slow_clock
                  SV <= sync2;
               end if;
            
				when sync2 =>
               if(slow_clock = '1') then
                  SV <= perase1;
               end if;           
            --------------------------------------------------
            when perase1 =>
               if(go and pdir=pleft and px > 4) then
                  x <= px + 8;   mem_wr <= '1';
               elsif(go and pdir=pright and px < screen_width - 14)
                  then  x <= px; mem_wr <= '1';
                  else  mem_wr <= '0';
               end if;
               y <= py;
               mem_in <= "000";
               SV <= perase2;
            when perase2 =>
               SV <= pupdate; 
            -------------------------------------------------- 
            when pupdate =>
               case pdir is
                  when pleft =>
                     if(go and px > 4) then
                        px <= px - 1;
                     end if;
                  when pright =>
                     if(go and px < screen_width - 14) then
                        px <= px + 1;
                     end if;
               end case;
               SV <= pdraw1;
            when pdraw1 =>
               if(go) then
                  if(pdir=pleft) then
                     x <= px;
                  else
                     x <= px + 8;
                  end if;
                  y <= py;
                  mem_wr <= '1';    
                  mem_in <= pcolor;
               end if;
               SV <= pdraw2;  
            when pdraw2 =>
               SV <= update1;             
            when update1 =>      --check up_left screen value
               x <= ballx - 1;   y <= bally - 1;
               mem_wr <= '0'; --read from video RAM
               SV <= update2;
            when update2 =>
               SV <= update3;
            when update3 =>
               ulv <= unsigned(mem_out);  --read screen
               y <= y + 2; 
               SV <= update4;
            when update4 =>      --check down_left
               SV <= update5;
            when update5 =>
               dlv <= unsigned(mem_out);
               x <= x + 2;
               SV <= update6;    
            when update6 =>      --check down right
               SV <= update7;
            when update7 =>
               drv <= unsigned(mem_out);
               y <= y - 2;
               SV <= update8; 
            when update8 =>      --check up right
               SV <= update9;
            when update9 =>
               urv <= unsigned(mem_out);
               SV <= update10;         
            when update10 =>
               case dir is
                  when ul =>
                     if(ulv/=0 and urv=0 and dlv/=0) then dir <= ur;
                        elsif(ulv/=0 and urv/=0 and dlv=0)then dir<=dl;
                           elsif(ulv/=0)then dir<=dr;
                              else dir <= ul;
                     end if;
                  when ur =>
                     if(urv/=0 and ulv=0 and drv/=0) then dir <= ul;
                        elsif(urv/=0 and ulv/=0 and drv=0)then dir<=dr;
                           elsif(urv/=0)then dir<=dl;
                              else dir <= ur;
                     end if;
                  when dl =>
                     if(dlv/=0 and drv=0 and ulv/=0) then dir <= dr;
                        elsif(dlv/=0 and drv/=0 and ulv=0)then dir<=ul;
                           elsif(dlv/=0)then dir<=ur;
                              else dir <= dl;
                     end if;
                  when dr =>
                     if(drv/=0 and dlv=0 and urv/=0) then dir <= dl;
                        elsif(drv/=0 and dlv/=0 and urv=0)then dir<=ur;
                           elsif(drv/=0)then dir<=ul;
                              else dir <= dr;
                     end if;
            
               end case;            
               SV <= erase1;
            --------------------------------------------------
            when erase1 =>
               x <= ballx;
               y <= bally;
               mem_wr <= '1'; 
               mem_in <= background;
               SV <= erase2;
            when erase2 =>
               SV <= bupdate;
            --------------------------------------------------
            when bupdate =>
               mem_wr <= '0';
               
               case dir is    
                  when ul =>
                     bally <= bally - 1;
                     ballx <= ballx - 1;
                  when ur =>
                     bally <= bally - 1;
                     ballx <= ballx + 1;
                  when dl =>
                     bally <= bally + 1;
                     ballx <= ballx - 1;
                  when dr =>
                     bally <= bally + 1;
                     ballx <= ballx + 1;
               end case;
               
               if(bally = 59) then
                  SV <= restart;
					else	
                  SV <= draw1;            
               end if;
               
            when draw1 =>
               x <= ballx;
               y <= bally;
               mem_wr <= '1';    
               mem_in <= bcolor;
               
               SV <= draw2;   
            when draw2 =>
               SV <= move0;
            --------------------------------------------------
            when others =>
               SV <= clean0;
         end case;
      end if;     
   end process;
end architecture DE1_SoC_MTL2;